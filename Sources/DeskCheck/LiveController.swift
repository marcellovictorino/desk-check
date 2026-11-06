@preconcurrency import AVFoundation
import DeskCheckCore
import SwiftUI

/// Live adjustment: the camera runs while the live view in the menu bar popover is showing, readings are averaged
/// over about a second, and the bands update as the desk or screen is moved. Stop, or closing the popover, turns the camera off.
@MainActor
final class LiveController: ObservableObject {
    static let shared = LiveController()
    /// The camera never stays on forever if the window is forgotten.
    static let maximumSeconds = 600.0
    nonisolated static let offText = "The camera is off."

    @Published private(set) var isRunning = false
    private var run = LiveRun()
    @Published private(set) var advice: [LiveAdvice] = []
    @Published private(set) var statusText = LiveController.offText
    @Published private(set) var setupName = ""
    /// Adjustable rows of the setup in use; the live view reserves room for them so Stop never moves.
    @Published private(set) var rowCount = 3

    /// True from pressing Live until the camera permission answer arrives. The system prompt takes focus from the popover,
    /// which must not count as clicking away.
    private(set) var awaitingPermission = false
    /// Set by the popover; whether its window is still on screen.
    var popoverIsVisible: () -> Bool = { true }

    private var sampler: LiveSampler?
    private var average = RollingAverage()
    private var profile = SetupProfile.external(name: "")
    private var camera = CameraModel(fieldOfViewDegrees: DeskConfig.typicalFieldOfViewDegrees)
    private var lastFace = 0.0
    private var timeout: Task<Void, Never>?

    func start() {
        guard let token = run.start() else { return }
        isRunning = true
        statusText = "Starting the camera…"
        // Which setup's rows to reserve space for is known before the camera opens.
        let profile = ConfigLocation.load().activeProfile
        setupName = profile.name
        rowCount = Adjustment.allCases.filter { $0 != .chairHeight && !profile.fixed.contains($0) }.count
        awaitingPermission = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                // An answer for a session that was stopped, or stopped and restarted, is ignored.
                guard self.run.isCurrent(token) else { return }
                self.awaitingPermission = false
                // The popover was closed while the prompt was up: nobody is watching, so the camera stays off.
                guard self.popoverIsVisible() else { self.stop(); return }
                guard granted else { self.fail("Desk Check has no camera permission. Allow it in System Settings, Privacy & Security, Camera."); return }
                self.begin(token)
            }
        }
    }

    private func begin(_ token: Int) {
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
            Task { @MainActor in if self.run.isCurrent(token) { self.receive(eyes, at: time) } }
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

    /// The popover was hidden or lost focus. Ignored while the permission prompt is up, because the prompt causes it.
    func popoverHidden() {
        guard !awaitingPermission else { return }
        stop()
    }

    func stop(reason: String = LiveController.offText) {
        awaitingPermission = false
        timeout?.cancel(); timeout = nil
        sampler?.stop(); sampler = nil
        if run.stop() { log.notice("live session stopped") }
        isRunning = false
        advice = []
        statusText = reason
    }

    private func fail(_ message: String) {
        sampler?.stop(); sampler = nil
        run.stop()
        isRunning = false
        statusText = message
    }
}
