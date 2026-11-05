@preconcurrency import AVFoundation
import DeskUndoCore
import SwiftUI

/// Runs one on-demand check: opens the camera, reads the eyes, closes the camera, explains the result.
@MainActor
final class PostureChecker: ObservableObject {
    static let shared = PostureChecker()

    @Published private(set) var permissionText = "unknown"
    @Published private(set) var statusText = "The camera is off."
    @Published private(set) var isRunning = false
    @Published private(set) var reading: PostureReading?
    @Published private(set) var advice: [Advice] = []
    @Published private(set) var webcamName: String?
    @Published private(set) var calibrationNote: String?
    @Published private(set) var preview: PreviewFrame?
    /// Set by a calibration run so Settings can show what changed.
    @Published private(set) var lastCalibrationText: String?

    func refreshPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionText = Self.describe(status)
        webcamName = FaceSampler.preferredCamera()?.localizedName
        log.notice("camera permission \(self.permissionText, privacy: .public)")
    }

    func clearPreview() { preview = nil }

    /// Reads where the eyes are and says what to move.
    func check() { start(calibrating: false) }

    /// Sit at the tape-measured distance, then calibrate: stores this webcam's field of view and tilt.
    func calibrate() { start(calibrating: true) }

    private func start(calibrating: Bool) {
        guard !isRunning else { return }
        isRunning = true
        preview = nil
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.refreshPermission()
                guard granted else {
                    self.finish("Desk Undo has no camera permission. Allow it in System Settings, Privacy & Security, Camera.")
                    return
                }
                self.begin(calibrating: calibrating)
            }
        }
    }

    private func begin(calibrating: Bool) {
        guard let device = FaceSampler.preferredCamera() else { finish("No camera found."); return }
        let config = ConfigLocation.load()
        if calibrating, config.setup.screenDistanceCm == nil {
            finish("Enter your tape-measured screen distance in Settings first.")
            return
        }
        statusText = "Camera on: \(device.localizedName). Look at the screen…"
        log.notice("camera session starting on \(device.localizedName, privacy: .public)")
        let sampler = FaceSampler(wantPreview: config.showPreview) { frame in
            Task { @MainActor in self.preview = frame }
        }
        sampler.run(device: device) { result, error in
            Task { @MainActor in
                if let error { self.finish(error); return }
                guard let result else { self.finish("No reading."); return }
                log.notice("camera session stopped, samples=\(result.samples.count, privacy: .public)")
                if calibrating { self.finishCalibration(result) } else { self.finishCheck(result) }
            }
        }
    }

    private func finishCheck(_ result: SampleResult) {
        let config = ConfigLocation.load()
        let camera = config.camera(forWebcam: result.cameraName, fieldOfViewDegrees: result.fieldOfViewDegrees)
        let readings = result.samples.compactMap { Geometry.reading($0, camera: camera, setup: config.setup) }
        guard let median = Geometry.median(readings) else {
            finish("No face found. Sit facing the screen with your face lit. The camera is off.")
            return
        }
        reading = median
        advice = AdviceEngine.advise(median)
        calibrationNote = config.calibration(forWebcam: result.cameraName).focalWidths == nil
            ? "This webcam is not calibrated, so distances are estimates. Calibrate it in Settings." : nil
        let line = String(format: "distance=%.1f eyeAboveTop=%.1f eyeHeight=%.1f frames=%d", median.distanceCm,
                          median.eyeAboveScreenTopCm, median.eyeHeightAboveDeskCm, readings.count)
        log.notice("check \(line, privacy: .public)")
        finish("Checked with \(result.cameraName). The camera is off.")
    }

    private func finishCalibration(_ result: SampleResult) {
        var config = ConfigLocation.load()
        let setup = config.setup
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
