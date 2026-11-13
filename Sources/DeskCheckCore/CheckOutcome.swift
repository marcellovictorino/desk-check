import Foundation

/// What the camera sessions tell the person, and the calibration maths behind it, with no camera or UI.
public enum CheckOutcome {
    public static let cameraOff = "The camera is off."

    public static let noFace = "No face found. Sit facing the screen with your face lit. The camera is off."

    public static let notCalibratedNote =
        "This webcam is not calibrated, so distances are estimates. Calibrate it in Settings."

    /// The status line after a plain check.
    public static func checked(passed: Bool, setupName: String, cameraName: String) -> String {
        (passed ? "Desk check passed" : "Checked") + " for \(setupName) with \(cameraName). The camera is off."
    }

    // MARK: Remember

    /// `config` is set when the remembered view should be saved; the person reads `message` either way.
    public struct RememberOutcome: Equatable {
        public var config: DeskConfig?
        public var message: String
    }

    /// Stores what the camera sees now as the remembered view of the preset for `posture`.
    public static func remember(_ r: PostureReading, posture: Posture, config: DeskConfig,
                                profile: SetupProfile) -> RememberOutcome {
        guard var preset = profile.presets[posture] else {
            return RememberOutcome(config: nil, message: "Enter the \(posture.label.lowercased()) desk height from the tape in Settings first. The camera is off.")
        }
        preset.distanceCm = r.distanceCm
        preset.eyeAboveScreenTopCm = r.eyeAboveScreenTopCm
        var p = profile
        p.presets[posture] = preset
        var updated = config
        updated.save(p)
        return RememberOutcome(config: updated, message: "Remembered \(posture.label.lowercased()) at \(Int(preset.deskHeightCm.rounded())) cm for \(profile.name). The camera is off.")
    }

    public static func saveFailed(_ reason: String) -> String { "Could not save: \(reason)" }

    // MARK: Confirm

    /// `note` is the sentence shown beside the preset, when there is one.
    public struct ConfirmOutcome: Equatable {
        public var note: String?
        public var message: String
    }

    public static func confirm(_ r: PostureReading, posture: Posture, profile: SetupProfile) -> ConfirmOutcome {
        guard let preset = profile.presets[posture] else {
            return ConfirmOutcome(note: nil, message: "No \(posture.label.lowercased()) preset in this setup. The camera is off.")
        }
        let height = Int(preset.deskHeightCm.rounded())
        let note: String
        switch preset.confirm(r) {
        case .confirmed: note = "\(posture.label) confirmed at \(height) cm."
        case .differs(let why): note = why
        case .notRemembered: note = "Use Remember view at \(height) cm first, so there is something to confirm."
        }
        return ConfirmOutcome(note: note, message: "Camera is off.")
    }

    // MARK: Calibrate

    public enum CalibrationOutcome: Equatable {
        case needsTapeDistance
        case noFace
        /// `summary` tells the person what was stored.
        case calibrated(WebcamCalibration, summary: String)

        /// The status line, which the checker shows once the session ends.
        public var message: String {
            switch self {
            case .needsTapeDistance: return "Enter your tape-measured screen distance first."
            case .noFace: return "No face found, so nothing was calibrated. The camera is off."
            case .calibrated(_, let summary): return "\(summary) The camera is off."
            }
        }
    }

    /// Calibrates the webcam's focal length, and its tilt when the setup holds the heights it needs.
    public static func calibrate(_ samples: [EyePoints], setup: Setup, cameraName: String) -> CalibrationOutcome {
        guard let tape = setup.screenDistanceCm else { return .needsTapeDistance }
        let focals = samples.compactMap { Geometry.calibrateFocal($0, tapeDistanceCm: tape) }
        guard let focal = Geometry.median(focals) else { return .noFace }
        var calibration = WebcamCalibration(focalWidths: focal, pitchDegrees: 0)
        var text = String(format: "Calibrated %@ at %.0f cm.", cameraName, tape)
        if let top = setup.screenTopHeightCm, let eye = setup.seatedEyeHeightCm {
            let lens = top + setup.lensOffset
            let pitches = samples.compactMap {
                Geometry.calibratePitch($0, focalWidths: focal, tapeDistanceCm: tape, lensHeightAboveDeskCm: lens, eyeHeightAboveDeskCm: eye)
            }
            if let pitch = Geometry.median(pitches) {
                calibration.pitchDegrees = pitch * 180 / .pi
                text += String(format: " Lens tilt %.1f°.", calibration.pitchDegrees ?? 0)
            }
        } else {
            text += " Tilt not calibrated: add screen top height and seated eye height."
        }
        return .calibrated(calibration, summary: text)
    }
}
