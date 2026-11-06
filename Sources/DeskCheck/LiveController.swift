@preconcurrency import AVFoundation
import DeskCheckCore
import SwiftUI

/// Live adjustment: the camera runs while the live window is open, readings are averaged over about
/// a second, and the bands update as the desk or screen is moved. Closing the window turns the camera off.
@MainActor
final class LiveController: ObservableObject {
    static let shared = LiveController()
    /// The camera never stays on forever if the window is forgotten.
    static let maximumSeconds = 600.0

    @Published private(set) var isRunning = false
    @Published private(set) var advice: [LiveAdvice] = []
    @Published private(set) var statusText = "The camera is off."
    @Published private(set) var setupName = ""

    private var sampler: LiveSampler?
    private var average = RollingAverage()
    private var profile = SetupProfile.external(name: "")
    private var camera = CameraModel(fieldOfViewDegrees: DeskConfig.typicalFieldOfViewDegrees)
    private var lastFace = 0.0
    private var timeout: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "Starting the camera…"
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                guard self.isRunning else { return }
                guard granted else { self.fail("Desk Check has no camera permission. Allow it in System Settings, Privacy & Security, Camera."); return }
                self.begin()
            }
        }
    }

    private func begin() {
        let config = ConfigLocation.load()
        profile = config.activeProfile
        setupName = profile.name
        guard let device = FaceSampler.camera(for: profile.camera) else {
            fail(profile.camera == .auto ? "No camera found." : "The camera for setup \(profile.name) is not connected.")
            return
        }
        camera = config.camera(forWebcam: device.localizedName, fieldOfViewDegrees: nil)
        average.reset(); advice = []
        lastFace = ProcessInfo.processInfo.systemUptime
        let sampler = LiveSampler { eyes, time in
            Task { @MainActor in self.receive(eyes, at: time) }
        }
        do { try sampler.start(device: device) } catch {
            fail("The camera could not open: \(error.localizedDescription)")
            return
        }
        self.sampler = sampler
        statusText = "Camera on (\(profile.name)): \(device.localizedName). Move the desk or screen."
        log.notice("live session starting on \(device.localizedName, privacy: .public)")
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumSeconds))
            if !Task.isCancelled { self?.stop(reason: "Live mode stopped after 10 minutes.") }
        }
    }

    private func receive(_ eyes: EyePoints?, at time: TimeInterval) {
        guard isRunning else { return }
        if let eyes, let r = Geometry.reading(eyes, camera: camera, setup: profile.measurements) {
            lastFace = time
            average.add(r, at: time)
            if let avg = average.average {
                advice = LiveEngine.advise(avg, setup: profile.measurements, fixed: profile.fixed)
                statusText = "Camera on (\(profile.name)). Updating about every second."
            }
        } else if time - lastFace > 2 {
            average.reset(); advice = []
            statusText = "No face found. Look at the screen with your face lit."
        }
    }

    func stop(reason: String = "The camera is off.") {
        timeout?.cancel(); timeout = nil
        sampler?.stop(); sampler = nil
        if isRunning { log.notice("live session stopped") }
        isRunning = false
        advice = []
        statusText = reason
    }

    private func fail(_ message: String) {
        sampler?.stop(); sampler = nil
        isRunning = false
        statusText = message
    }
}
