@preconcurrency import AVFoundation
import DeskCheckCore
import SwiftUI

/// Runs one on-demand check: opens the camera, reads the eyes, closes the camera, explains the result.
@MainActor
final class PostureChecker: NSObject, ObservableObject {
    static let shared = PostureChecker()

    @Published private(set) var permissionText = "unknown"
    @Published private(set) var statusText = "The camera is off."
    @Published private(set) var isRunning = false
    @Published private(set) var reading: PostureReading?
    @Published private(set) var advice: [Advice] = []
    @Published private(set) var webcamName: String?
    @Published private(set) var calibrationNote: String?
    @Published private(set) var presetNote: String?
    @Published private(set) var preview: PreviewFrame?
    /// Set by a calibration run so Settings can show what changed.
    @Published private(set) var lastCalibrationText: String?

    /// True while the popover shows Settings in place of the main view.
    @Published var showingSettings = false
    @Published private(set) var setupNames: [String] = []
    @Published private(set) var activeSetup = ""
    @Published private(set) var settingsWarning: String?
    @Published var choosingSettingsFile = false
    private var observers: [NSObjectProtocol] = []

    let settings: SettingsFile
    let live: LiveController

    init(settings: SettingsFile = ConfigLocation.settings) {
        self.settings = settings
        self.live = LiveController(settings: settings)
        super.init()
        reloadSetups()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.camerasChanged() }
            })
        }
    }

    /// Re-reads the setup list and the setup in use from the config file.
    func reloadSetups() {
        let config = settings.load()
        settingsWarning = settings.loadWarning
        setupNames = settingsWarning == nil ? config.setupNames : []
        activeSetup = settingsWarning == nil ? config.activeSetupName : "Settings unavailable"
        webcamName = FaceSampler.camera(for: config.activeProfile.camera)?.localizedName
    }

    func selectSetup(_ name: String) {
        var config = settings.load()
        guard config.setupNames.contains(name) else { return }
        config.activeSetupName = name
        do { try settings.save(config) }
        catch { settingsWarning = "Could not save settings: \(error.localizedDescription)"; return }
        reset()
        reloadSetups()
    }

    /// With auto switching on, a webcam plugged in or out moves to the setup that fits what is connected.
    private func camerasChanged() {
        let config = settings.load()
        if config.autoSwitch {
            let cameras = FaceSampler.connectedCameras()
            let external = cameras.filter { $0.deviceType == .external }.map(\.localizedName)
            let builtIn = cameras.filter { $0.deviceType != .external }.map(\.localizedName)
            if let name = config.suggestedSetup(externalCameras: external, builtInCameras: builtIn), name != config.activeSetupName {
                log.notice("auto-switching setup to \(name, privacy: .public)")
                selectSetup(name)
                return
            }
        }
        reloadSetups()
    }

    /// Forgets the last result, which belonged to another setup.
    func reset() {
        reading = nil; advice = []; calibrationNote = nil; presetNote = nil; preview = nil
        statusText = "The camera is off."
    }

    func refreshPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionText = Self.describe(status)
        webcamName = FaceSampler.camera(for: settings.load().activeProfile.camera)?.localizedName
        log.notice("camera permission \(self.permissionText, privacy: .public)")
    }

    func clearPreview() { preview = nil }

    /// Reads where the eyes are and says what to move.
    func check() { start(.check) }

    /// Sit at the tape-measured distance, then calibrate: stores this webcam's field of view and tilt.
    func calibrate() { start(.calibrate) }

    /// Saves what the camera sees now as the remembered view of a preset, so later checks can confirm it.
    func rememberView(_ posture: Posture) { start(.remember(posture)) }

    /// Checks the camera view against a preset's remembered view.
    func confirmPreset(_ posture: Posture) { start(.confirm(posture)) }

    enum Mode: Equatable { case check, calibrate, remember(Posture), confirm(Posture) }

    private func start(_ mode: Mode) {
        guard !isRunning else { return }
        _ = settings.load()
        settingsWarning = settings.loadWarning
        guard settingsWarning == nil else { return }
        isRunning = true
        preview = nil
        presetNote = nil
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.refreshPermission()
                guard granted else {
                    self.finish("Desk Check has no camera permission. Allow it in System Settings, Privacy & Security, Camera.")
                    return
                }
                self.begin(mode)
            }
        }
    }

    private func begin(_ mode: Mode) {
        let calibrating = mode == .calibrate
        let config = settings.load()
        let profile = config.activeProfile
        guard let device = FaceSampler.camera(for: profile.camera) else {
            finish(profile.camera == .auto ? "No camera found." : "The camera for setup \(profile.name) is not connected.")
            return
        }
        if calibrating, profile.measurements.screenDistanceCm == nil {
            finish("Enter your tape-measured screen distance in Settings first.")
            return
        }
        statusText = "Camera on (\(profile.name)): \(device.localizedName). Look at the screen…"
        log.notice("camera session starting on \(device.localizedName, privacy: .public)")
        let sampler = FaceSampler(wantPreview: config.showPreview) { frame in
            Task { @MainActor in self.preview = frame }
        }
        sampler.run(device: device) { result, error in
            Task { @MainActor in
                if let error { self.finish(error); return }
                guard let result else { self.finish("No reading."); return }
                log.notice("camera session stopped, samples=\(result.samples.count, privacy: .public)")
                if calibrating { self.finishCalibration(result) } else { self.finishCheck(result, mode: mode) }
            }
        }
    }

    private func finishCheck(_ result: SampleResult, mode: Mode) {
        let config = settings.load()
        let camera = config.camera(forWebcam: result.cameraName, fieldOfViewDegrees: result.fieldOfViewDegrees)
        let profile = config.activeProfile
        let readings = result.samples.compactMap { Geometry.reading($0, camera: camera, setup: profile.measurements) }
        guard let median = Geometry.median(readings) else {
            finish(CheckOutcome.noFace)
            return
        }
        reading = median
        advice = AdviceEngine.advise(median, fixed: profile.fixed)
        calibrationNote = config.calibration(forWebcam: result.cameraName).focalWidths == nil
            ? CheckOutcome.notCalibratedNote : nil
        let line = String(format: "distance=%.1f eyeAboveTop=%.1f eyeHeight=%.1f frames=%d", median.distanceCm,
                          median.eyeAboveScreenTopCm, median.eyeHeightAboveDeskCm, readings.count)
        log.notice("check \(line, privacy: .public)")
        let passed = advice.allSatisfy { $0.status != .adjust }
        var message = CheckOutcome.checked(passed: passed, setupName: profile.name, cameraName: result.cameraName)
        switch mode {
        case .remember(let posture): message = remember(median, posture: posture, config: config, profile: profile)
        case .confirm(let posture): message = confirm(median, posture: posture, profile: profile)
        default: break
        }
        finish(message)
    }

    private func remember(_ r: PostureReading, posture: Posture, config: DeskConfig, profile: SetupProfile) -> String {
        let outcome = CheckOutcome.remember(r, posture: posture, config: config, profile: profile)
        guard let updated = outcome.config else { return outcome.message }
        do { try settings.save(updated) } catch { return CheckOutcome.saveFailed(error.localizedDescription) }
        presetNote = nil
        return outcome.message
    }

    private func confirm(_ r: PostureReading, posture: Posture, profile: SetupProfile) -> String {
        let outcome = CheckOutcome.confirm(r, posture: posture, profile: profile)
        presetNote = outcome.note
        return outcome.message
    }

    private func finishCalibration(_ result: SampleResult) {
        var config = settings.load()
        let outcome = CheckOutcome.calibrate(result.samples, setup: config.activeProfile.measurements, cameraName: result.cameraName)
        if case .calibrated(let calibration, let text) = outcome {
            config.setCalibration(calibration, forWebcam: result.cameraName)
            do {
                try settings.save(config)
                lastCalibrationText = text
                log.notice("calibration saved \(text, privacy: .public)")
            } catch {
                lastCalibrationText = "Could not save the calibration: \(error.localizedDescription)"
            }
        }
        finish(outcome.message)
    }

    private func finish(_ message: String) {
        statusText = message
        isRunning = false
    }

    static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "allowed"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }
}
