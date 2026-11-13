import Foundation
import Testing
@testable import DeskCheckCore

/// Intent source: DESK-58 recommendation 5, approved by the captain ("apply all recommendations"): the result
/// sentences, remember/confirm and calibration maths live in the core so tests can pin them, with behaviour
/// unchanged from when they sat in PostureChecker. Sentences are pinned because people read them.
@Suite struct CheckOutcomeTests {
    let reading = PostureReading(distanceCm: 61.4, eyeAboveScreenTopCm: 4.6, eyeHeightAboveDeskCm: 50)

    func profile(presets: [Posture: DeskPreset] = [:]) -> SetupProfile {
        SetupProfile(name: "Home", presets: presets)
    }

    @Test func checkedSentenceSaysPassedOrChecked() {
        #expect(CheckOutcome.checked(passed: true, setupName: "Home", cameraName: "C920")
                == "Desk check passed for Home with C920. The camera is off.")
        #expect(CheckOutcome.checked(passed: false, setupName: "Home", cameraName: "C920")
                == "Checked for Home with C920. The camera is off.")
    }

    // MARK: remember

    @Test func rememberStoresTheViewInThePreset() throws {
        let config = DeskConfig(text: DeskConfig.starterContents)
        let p = profile(presets: [.sit: DeskPreset(deskHeightCm: 72.4)])
        let outcome = CheckOutcome.remember(reading, posture: .sit, config: config, profile: p)
        #expect(outcome.message == "Remembered sit at 72 cm for Home. The camera is off.")
        let saved = try #require(outcome.config).profile(named: "Home").presets[.sit]
        #expect(saved == DeskPreset(deskHeightCm: 72.4, distanceCm: 61.4, eyeAboveScreenTopCm: 4.6))
    }

    @Test func rememberWithoutDeskHeightSavesNothing() {
        let outcome = CheckOutcome.remember(reading, posture: .stand, config: DeskConfig(text: ""), profile: profile())
        #expect(outcome.config == nil)
        #expect(outcome.message == "Enter the stand desk height from the tape in Settings first. The camera is off.")
    }

    @Test func saveFailureNamesTheReason() {
        #expect(CheckOutcome.saveFailed("disk full") == "Could not save: disk full")
    }

    // MARK: confirm

    @Test func confirmWithinToleranceIsConfirmed() {
        let p = profile(presets: [.sit: DeskPreset(deskHeightCm: 72.4, distanceCm: 63, eyeAboveScreenTopCm: 3)])
        let outcome = CheckOutcome.confirm(reading, posture: .sit, profile: p)  // 1.6 cm off on both
        #expect(outcome == .init(note: "Sit confirmed at 72 cm.", message: "Camera is off."))
    }

    @Test func confirmBeyondToleranceSaysWhatDiffers() {
        let p = profile(presets: [.sit: DeskPreset(deskHeightCm: 72, distanceCm: 55, eyeAboveScreenTopCm: 4.6)])
        let outcome = CheckOutcome.confirm(reading, posture: .sit, profile: p)  // 6.4 cm further
        #expect(outcome.note == "The screen is 6 cm further than when you saved it. Check the tape reading.")
        #expect(outcome.message == "Camera is off.")
    }

    @Test func confirmBeforeRememberingExplainsWhat() {
        let p = profile(presets: [.stand: DeskPreset(deskHeightCm: 110.5)])
        #expect(CheckOutcome.confirm(reading, posture: .stand, profile: p).note
                == "Use Remember view at 111 cm first, so there is something to confirm.")
    }

    @Test func confirmWithoutPresetLeavesTheNoteEmpty() {
        let outcome = CheckOutcome.confirm(reading, posture: .stand, profile: profile())
        #expect(outcome.note == nil)
        #expect(outcome.message == "No stand preset in this setup. The camera is off.")
    }

    // MARK: calibrate

    /// Frames of a person 62 cm away through a 70.4 degree webcam whose lens sits 5 cm below their eyes,
    /// the same model the geometry tests use.
    let camera = CameraModel(fieldOfViewDegrees: 70.4)
    func frame(midY: Double) -> EyePoints {
        let span = camera.focalWidths * 1920 * Geometry.defaultEyeSpanCm / 62
        return EyePoints(left: .init(x: 960 - span / 2, y: midY), right: .init(x: 960 + span / 2, y: midY),
                         imageWidth: 1920, imageHeight: 1080, yaw: 0)
    }

    @Test func calibrationWithoutTapeDistanceAsksForIt() {
        let outcome = CheckOutcome.calibrate([frame(midY: 540)], setup: Setup(), cameraName: "C920")
        #expect(outcome == .needsTapeDistance)
        #expect(outcome.message == "Enter your tape-measured screen distance first.")
    }

    @Test func calibrationWithoutFacesStoresNothing() {
        let outcome = CheckOutcome.calibrate([], setup: Setup(screenDistanceCm: 62), cameraName: "C920")
        #expect(outcome == .noFace)
        #expect(outcome.message == "No face found, so nothing was calibrated. The camera is off.")
    }

    @Test func calibrationWithoutHeightsLeavesTiltAlone() throws {
        let outcome = CheckOutcome.calibrate([frame(midY: 540)], setup: Setup(screenDistanceCm: 62), cameraName: "C920")
        guard case .calibrated(let c, let summary) = outcome else { Issue.record("not calibrated"); return }
        #expect(abs(try #require(c.focalWidths) - camera.focalWidths) < 1e-9)
        #expect(c.pitchDegrees == 0)
        #expect(summary == "Calibrated C920 at 62 cm. Tilt not calibrated: add screen top height and seated eye height.")
        #expect(outcome.message == summary + " The camera is off.")
    }

    @Test func calibrationWithHeightsFindsTheLensTilt() throws {
        // Lens at 40 cm, eyes seated at 45 cm, 62 cm away: the eyes should sit above the frame centre.
        let setup = Setup(screenDistanceCm: 62, screenTopHeightCm: 39, lensOffsetCm: 1, seatedEyeHeightCm: 45)
        let tilt = 3.0 * .pi / 180
        let expected = atan(5.0 / 62)
        let midY = 540 + tan(expected - tilt) * camera.focalWidths * 1920
        let outcome = CheckOutcome.calibrate([frame(midY: midY), frame(midY: midY)], setup: setup, cameraName: "C920")
        guard case .calibrated(let c, let summary) = outcome else { Issue.record("not calibrated"); return }
        #expect(abs(try #require(c.pitchDegrees) - 3.0) < 0.01)
        #expect(summary == "Calibrated C920 at 62 cm. Lens tilt 3.0°.")
    }

    @Test func implausibleTiltIsDroppedNotStored() throws {
        let setup = Setup(screenDistanceCm: 62, screenTopHeightCm: 39, lensOffsetCm: 1, seatedEyeHeightCm: 45)
        let outcome = CheckOutcome.calibrate([frame(midY: 1600)], setup: setup, cameraName: "C920")
        guard case .calibrated(let c, let summary) = outcome else { Issue.record("not calibrated"); return }
        #expect(c.pitchDegrees == 0)
        #expect(summary == "Calibrated C920 at 62 cm.")
    }
}

/// Intent source: the same recommendation, "remove the duplicate median": one median serves readings and calibration.
@Suite struct MedianTests {
    @Test func emptyHasNoMedian() { #expect(Geometry.median([Double]()) == nil) }
    @Test func oddCountTakesTheMiddle() { #expect(Geometry.median([9, 1, 5]) == 5) }
    @Test func evenCountAveragesTheMiddlePair() { #expect(Geometry.median([4, 1, 100, 2]) == 3) }
    @Test func oneBadValueDoesNotMoveIt() { #expect(Geometry.median([60, 61, 500, 59, 60]) == 60) }
}
