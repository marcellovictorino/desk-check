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
    private var observers: [NSObjectProtocol] = []

    override init() {
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
        let config = ConfigLocation.load()
        setupNames = config.setupNames
        activeSetup = config.activeSetupName
        webcamName = FaceSampler.camera(for: config.activeProfile.camera)?.localizedName
    }

    func selectSetup(_ name: String) {
        var config = ConfigLocation.load()
        guard config.setupNames.contains(name) else { return }
        config.activeSetupName = name
        try? ConfigLocation.save(config)
        reset()
        reloadSetups()
    }

    /// With auto switching on, a webcam plugged in or out moves to the setup that fits what is connected.
    private func camerasChanged() {
        let config = ConfigLocation.load()
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
        webcamName = FaceSampler.camera(for: ConfigLocation.load().activeProfile.camera)?.localizedName
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
        let config = ConfigLocation.load()
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
        let config = ConfigLocation.load()
        let camera = config.camera(forWebcam: result.cameraName, fieldOfViewDegrees: result.fieldOfViewDegrees)
        let profile = config.activeProfile
        let readings = result.samples.compactMap { Geometry.reading($0, camera: camera, setup: profile.measurements) }
        guard let median = Geometry.median(readings) else {
            finish("No face found. Sit facing the screen with your face lit. The camera is off.")
            return
        }
        reading = median
        advice = AdviceEngine.advise(median, fixed: profile.fixed)
        calibrationNote = config.calibration(forWebcam: result.cameraName).focalWidths == nil
            ? "This webcam is not calibrated, so distances are estimates. Calibrate it in Settings." : nil
        let line = String(format: "distance=%.1f eyeAboveTop=%.1f eyeHeight=%.1f frames=%d", median.distanceCm,
                          median.eyeAboveScreenTopCm, median.eyeHeightAboveDeskCm, readings.count)
        log.notice("check \(line, privacy: .public)")
        let passed = advice.allSatisfy { $0.status != .adjust }
        var message = (passed ? "Desk check passed" : "Checked") + " for \(profile.name) with \(result.cameraName). The camera is off."
        switch mode {
        case .remember(let posture): message = remember(median, posture: posture, config: config, profile: profile)
        case .confirm(let posture): message = confirm(median, posture: posture, profile: profile)
        default: break
        }
        finish(message)
    }

    private func remember(_ r: PostureReading, posture: Posture, config: DeskConfig, profile: SetupProfile) -> String {
        guard var preset = profile.presets[posture] else {
            return "Enter the \(posture.label.lowercased()) desk height from the tape in Settings first. The camera is off."
        }
        preset.distanceCm = r.distanceCm
        preset.eyeAboveScreenTopCm = r.eyeAboveScreenTopCm
        var p = profile
        p.presets[posture] = preset
        var updated = config
        updated.save(p)
        do { try ConfigLocation.save(updated) } catch { return "Could not save: \(error.localizedDescription)" }
        presetNote = nil
        return "Remembered \(posture.label.lowercased()) at \(Int(preset.deskHeightCm.rounded())) cm for \(profile.name). The camera is off."
    }

    private func confirm(_ r: PostureReading, posture: Posture, profile: SetupProfile) -> String {
        guard let preset = profile.presets[posture] else { return "No \(posture.label.lowercased()) preset in this setup. The camera is off." }
        switch preset.confirm(r) {
        case .confirmed: presetNote = "\(posture.label) confirmed at \(Int(preset.deskHeightCm.rounded())) cm."
        case .differs(let why): presetNote = why
        case .notRemembered: presetNote = "Use Remember view at \(Int(preset.deskHeightCm.rounded())) cm first, so there is something to confirm."
        }
        return "Camera is off."
    }

    private func finishCalibration(_ result: SampleResult) {
        var config = ConfigLocation.load()
        let setup = config.activeProfile.measurements
        guard let tape = setup.screenDistanceCm else { finish("Enter your tape-measured screen distance first."); return }
        let focals = result.samples.compactMap { Geometry.calibrateFocal($0, tapeDistanceCm: tape) }
        guard let focal = Self.median(focals) else {
            finish("No face found, so nothing was calibrated. The camera is off.")
            return
        }
        var calibration = WebcamCalibration(focalWidths: focal, pitchDegrees: 0)
        var text = String(format: "Calibrated %@ at %.0f cm.", result.cameraName, tape)
        if let top = setup.screenTopHeightCm, let eye = setup.seatedEyeHeightCm {
            let lens = top + setup.lensOffset
            let pitches = result.samples.compactMap {
                Geometry.calibratePitch($0, focalWidths: focal, tapeDistanceCm: tape, lensHeightAboveDeskCm: lens, eyeHeightAboveDeskCm: eye)
            }
            if let pitch = Self.median(pitches) {
                calibration.pitchDegrees = pitch * 180 / .pi
                text += String(format: " Lens tilt %.1f°.", calibration.pitchDegrees ?? 0)
            }
        } else {
            text += " Tilt not calibrated: add screen top height and seated eye height."
        }
        config.setCalibration(calibration, forWebcam: result.cameraName)
        do {
            try ConfigLocation.save(config)
            lastCalibrationText = text
            log.notice("calibration saved \(text, privacy: .public)")
        } catch {
            lastCalibrationText = "Could not save the calibration: \(error.localizedDescription)"
        }
        finish("\(text) The camera is off.")
    }

    private func finish(_ message: String) {
        statusText = message
        isRunning = false
    }

    private static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
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
