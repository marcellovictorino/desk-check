import XCTest
@testable import DeskUndoCore

/// Intent sources: the piece 2 brief (SCR-705) asks for distance and height readings within
/// 3 cm and 2 cm, tape-measure inputs with defaults until measured, per-webcam calibration,
/// one sentence of advice with a number per adjustment, and a config file that allows comments.
final class GeometryTests: XCTestCase {
    /// A Logitech C920 frame, 1920 x 1080, with a person 62 cm away whose eyes sit 4 cm above the lens axis.
    /// The pixel numbers come from the pinhole model for a 70.4 degree field of view; the A/B desk test
    /// with a real webcam is the check against the real world.
    let camera = CameraModel(fieldOfViewDegrees: 70.4)
    func eyes(span: Double, midY: Double, yaw: Double = 0) -> EyePoints {
        EyePoints(left: .init(x: 960 - span / 2, y: midY), right: .init(x: 960 + span / 2, y: midY),
                  imageWidth: 1920, imageHeight: 1080, yaw: yaw)
    }

    func testDistanceAndHeightFromEyePoints() throws {
        let focalPx = camera.focalWidths * 1920
        let span = focalPx * 6.3 / 62
        let midY = 540 + focalPx * (4.0 / 62)
        let r = try XCTUnwrap(Geometry.reading(eyes(span: span, midY: midY), camera: camera,
                                               setup: Setup(screenTopHeightCm: 50, lensOffsetCm: 1.5)))
        XCTAssertEqual(r.distanceCm, 62, accuracy: 0.1)
        XCTAssertEqual(r.eyeAboveScreenTopCm, 5.5, accuracy: 0.2)   // 1.5 lens offset + 4 above the lens
        XCTAssertEqual(r.eyeHeightAboveDeskCm, 55.5, accuracy: 0.2)
    }

    func testMovingTheScreen5cmChangesTheReadingBy5cm() throws {
        let focalPx = camera.focalWidths * 1920
        func read(_ d: Double) -> Double {
            Geometry.reading(eyes(span: focalPx * 6.3 / d, midY: 540), camera: camera, setup: Setup())!.distanceCm
        }
        XCTAssertEqual(read(67) - read(62), 5, accuracy: 0.1)
    }

    func testTurnedHeadDoesNotReadAsFarther() throws {
        let focalPx = camera.focalWidths * 1920
        let yaw = 0.35
        let span = focalPx * 6.3 / 60 * cos(yaw)
        let r = try XCTUnwrap(Geometry.reading(eyes(span: span, midY: 540, yaw: yaw), camera: camera, setup: Setup()))
        XCTAssertEqual(r.distanceCm, 60, accuracy: 0.1)
    }

    func testFocalCalibrationFixesAWrongFieldOfView() throws {
        // The real lens is 78 degrees wide but the default assumes 65.
        let real = CameraModel(fieldOfViewDegrees: 78)
        let span = real.focalWidths * 1920 * 6.3 / 55           // person sits 55 cm away by tape
        let frame = eyes(span: span, midY: 540)
        let before = try XCTUnwrap(Geometry.reading(frame, camera: CameraModel(fieldOfViewDegrees: 60), setup: Setup()))
        XCTAssertGreaterThan(abs(before.distanceCm - 55), 3, "uncalibrated reading is off by more than the limit")
        let focal = try XCTUnwrap(Geometry.calibrateFocal(frame, tapeDistanceCm: 55))
        let after = try XCTUnwrap(Geometry.reading(frame, camera: CameraModel(focalWidths: focal), setup: Setup()))
        XCTAssertEqual(after.distanceCm, 55, accuracy: 0.1)
        // And the calibrated camera reads a different distance correctly.
        let moved = eyes(span: real.focalWidths * 1920 * 6.3 / 70, midY: 540)
        let reading = try XCTUnwrap(Geometry.reading(moved, camera: CameraModel(focalWidths: focal), setup: Setup()))
        XCTAssertEqual(reading.distanceCm, 70, accuracy: 0.1)
    }

    func testPitchCalibrationRecoversTiltedLens() throws {
        // Lens tilted up 6 degrees; eyes truly 3 cm above the lens axis height... measure at 60 cm.
        let tilt = 6.0 * .pi / 180
        let focalPx = camera.focalWidths * 1920
        let trueAngle = atan(8.0 / 60)                      // eyes 8 cm above the lens
        let midY = 540 + focalPx * tan(trueAngle - tilt)    // a lens tilted up sees the eyes lower
        let frame = eyes(span: focalPx * 6.3 / 60, midY: midY)
        let pitch = try XCTUnwrap(Geometry.calibratePitch(frame, focalWidths: camera.focalWidths, tapeDistanceCm: 60,
                                                         lensHeightAboveDeskCm: 40, eyeHeightAboveDeskCm: 48))
        XCTAssertEqual(pitch, tilt, accuracy: 0.002)
        let r = try XCTUnwrap(Geometry.reading(frame, camera: CameraModel(focalWidths: camera.focalWidths, pitch: pitch),
                                               setup: Setup(screenTopHeightCm: 39, lensOffsetCm: 1)))
        XCTAssertEqual(r.eyeHeightAboveDeskCm, 48, accuracy: 0.3)
    }

    func testMedianIgnoresOneBadFrame() {
        let good = PostureReading(distanceCm: 60, eyeAboveScreenTopCm: 4, eyeHeightAboveDeskCm: 50)
        let bad = PostureReading(distanceCm: 120, eyeAboveScreenTopCm: -30, eyeHeightAboveDeskCm: 10)
        XCTAssertEqual(Geometry.median([good, good, bad, good, good])?.distanceCm, 60)
    }

    func testNoReadingWithoutEyes() {
        XCTAssertNil(Geometry.reading(eyes(span: 0, midY: 540), camera: camera, setup: Setup()))
    }
}

final class AdviceTests: XCTestCase {
    func reading(_ d: Double, _ h: Double) -> PostureReading {
        PostureReading(distanceCm: d, eyeAboveScreenTopCm: h, eyeHeightAboveDeskCm: 0)
    }

    func testEachAdjustmentGetsOneSentenceWithANumber() {
        let advice = AdviceEngine.advise(reading(45, 15))
        XCTAssertEqual(advice.map(\.sentence), [
            "Move the screen 15 cm further away; it is 45 cm from your eyes.",
            "Raise the screen by 10 cm; your eyes are 15 cm above its top edge.",
        ])
    }

    func testTooFarAndScreenTooHigh() {
        let advice = AdviceEngine.advise(reading(80, -3))
        XCTAssertEqual(advice[0].sentence, "Move the screen 20 cm closer; it is 80 cm from your eyes.")
        XCTAssertEqual(advice[1].sentence, "Lower the screen by 8 cm; your eyes are 3 cm below its top edge.")
    }

    func testGoodPostureNeedsNoAdjustment() {
        let advice = AdviceEngine.advise(reading(62, 4))
        XCTAssertEqual(advice.map(\.status), [.good, .good])
    }
}

final class ConfigTests: XCTestCase {
    func testStarterFileHasOneStandingDeskSetupWithDefaults() {
        let c = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertEqual(c.setupNames, ["Standing desk"])
        XCTAssertEqual(c.activeSetupName, "Standing desk")
        let p = c.activeProfile
        XCTAssertEqual(p.camera, .auto)
        XCTAssertEqual(p.measurements.screenTop, 45)
        XCTAssertTrue(p.supportsStandingPreset)
        XCTAssertFalse(c.showPreview)
        XCTAssertFalse(c.autoSwitch)
    }

    func testAFileWithNoSetupsShowsADefaultSetup() {
        let c = DeskConfig(text: "# old file\n[preferences]\npreview = true\n")
        XCTAssertEqual(c.setupNames, ["Standing desk"])
    }

    func testMeasuredValuesReplaceDefaultsAndSurviveASave() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.activeProfile
        p.measurements = Setup(screenDistanceCm: 58.5, screenTopHeightCm: 47, lensOffsetCm: 2, userHeightCm: 181, seatedEyeHeightCm: 41)
        c.save(p)
        let reread = DeskConfig(text: c.document.text).activeProfile
        XCTAssertEqual(reread.measurements, p.measurements)
        XCTAssertTrue(c.document.text.contains("# Delete a measurement line to go back to the default estimate"))
    }

    func testHandWrittenCommentsAndOtherKeysSurviveAnEdit() {
        let text = """
        # my own note
        [setups."Desk"]
        screen_top_height_cm = 47 # tape, Monday
        custom_key = "keep me"

        [preferences]
        preview = true
        """
        var c = DeskConfig(text: text)
        var p = c.profile(named: "Desk")
        p.measurements.screenTopHeightCm = 50
        p.measurements.lensOffsetCm = 2
        c.save(p)
        XCTAssertTrue(c.document.text.contains("# my own note"))
        XCTAssertTrue(c.document.text.contains("screen_top_height_cm = 50 # tape, Monday"))
        XCTAssertTrue(c.document.text.contains("custom_key = \"keep me\""))
        XCTAssertEqual(c.profile(named: "Desk").measurements.lensOffsetCm, 2)
        XCTAssertTrue(c.showPreview)
    }

    // MARK: Setups (captain's requirement: a standing desk with an external camera and a MacBook on a normal desk)

    func twoSetups() -> DeskConfig {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var desk = c.profile(named: "Standing desk")
        desk.camera = .named("HD Pro Webcam C920")
        desk.measurements = Setup(screenDistanceCm: 62, screenTopHeightCm: 50, lensOffsetCm: 2)
        c.save(desk)
        var mac = SetupProfile.laptop(name: "MacBook")
        mac.measurements = Setup(screenDistanceCm: 45, screenTopHeightCm: 22)
        XCTAssertTrue(c.addSetup(mac))
        return c
    }

    func testTwoSetupsKeepTheirOwnCameraScreenAndMeasurements() {
        let c = DeskConfig(text: twoSetups().document.text)
        XCTAssertEqual(c.setupNames, ["Standing desk", "MacBook"])
        let desk = c.profile(named: "Standing desk"), mac = c.profile(named: "MacBook")
        XCTAssertEqual(desk.camera, .named("HD Pro Webcam C920"))
        XCTAssertEqual(desk.measurements.screenTopHeightCm, 50)
        XCTAssertEqual(mac.camera, .builtIn)
        XCTAssertEqual(mac.screen, "MacBook")
        XCTAssertEqual(mac.measurements.screenTopHeightCm, 22)
        XCTAssertEqual(mac.measurements.lensOffset, 0.5, "built-in camera defaults apply until measured")
        XCTAssertEqual(desk.measurements.lensOffset, 2)
    }

    func testSeatedOnlySetupHasNoStandingPresetAndFixedAdjustments() {
        let c = DeskConfig(text: twoSetups().document.text)
        let mac = c.profile(named: "MacBook")
        XCTAssertFalse(mac.supportsStandingPreset)
        XCTAssertEqual(mac.fixed, [.deskHeight, .screenHeight])
        XCTAssertTrue(c.profile(named: "Standing desk").supportsStandingPreset)
        XCTAssertTrue(c.document.text.contains("desk_height = \"fixed\""))
    }

    func testFixedAdjustmentIsReportedNotAdvised() {
        let r = PostureReading(distanceCm: 45, eyeAboveScreenTopCm: 15, eyeHeightAboveDeskCm: 0)
        let advice = AdviceEngine.advise(r, fixed: [.screenHeight])
        XCTAssertEqual(advice[0].status, .adjust)
        XCTAssertEqual(advice[1].status, .fixed)
        XCTAssertEqual(advice[1].sentence, "Screen height is fixed in this setup; your eyes are 15 cm above its top edge.")
    }

    func testLastUsedSetupIsRemembered() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        XCTAssertEqual(DeskConfig(text: c.document.text).activeSetupName, "MacBook")
        c.activeSetupName = "Gone"   // a setup that no longer exists falls back to the first
        XCTAssertEqual(DeskConfig(text: c.document.text).activeSetupName, "Standing desk")
    }

    func testRenameDuplicateAndDelete() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        XCTAssertTrue(c.renameSetup("MacBook", to: "Sofa"))
        XCTAssertEqual(c.activeSetupName, "Sofa", "renaming the active setup keeps it active")
        XCTAssertEqual(c.profile(named: "Sofa").camera, .builtIn)
        XCTAssertTrue(c.duplicateSetup("Standing desk", as: "Standing desk 2"))
        XCTAssertEqual(c.setupNames, ["Standing desk", "Standing desk 2", "Sofa"])
        XCTAssertEqual(c.profile(named: "Standing desk 2"), SetupProfile(name: "Standing desk 2", camera: .named("HD Pro Webcam C920"), screen: "external", measurements: c.profile(named: "Standing desk").measurements))
        XCTAssertTrue(c.deleteSetup("Sofa"))
        XCTAssertEqual(c.activeSetupName, "Standing desk")
        XCTAssertEqual(c.setupNames, ["Standing desk", "Standing desk 2"])
        XCTAssertTrue(c.deleteSetup("Standing desk 2"))
        XCTAssertFalse(c.deleteSetup("Standing desk"), "the last setup stays")
    }

    func testNamesMustBeNewAndNotEmpty() {
        var c = twoSetups()
        XCTAssertFalse(c.addSetup(.external(name: "")))
        XCTAssertFalse(c.addSetup(.external(name: "MacBook")))
        XCTAssertFalse(c.renameSetup("MacBook", to: "Standing desk"))
        XCTAssertFalse(c.duplicateSetup("MacBook", as: " "))
        XCTAssertEqual(c.setupNames.count, 2)
    }

    func testSetupNameWithQuotesAndDotsRoundTrips() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertTrue(c.addSetup(.laptop(name: "Mum's \"sofa\" v1.2")))
        XCTAssertEqual(DeskConfig(text: c.document.text).setupNames, ["Standing desk", "Mum's \"sofa\" v1.2"])
    }

    func testDuplicateKeepsCommentsOfTheCopiedSetup() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertTrue(c.duplicateSetup("Standing desk", as: "Copy"))
        XCTAssertEqual(c.document.text.components(separatedBy: "# Top edge of the screen above the desk surface").count - 1, 2)
    }

    // MARK: Auto-suggest

    func testExternalWebcamPluggedInSuggestsTheStandingDeskSetup() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        XCTAssertEqual(c.suggestedSetup(externalCameras: ["HD Pro Webcam C920"], builtInCameras: ["MacBook Pro Camera"]), "Standing desk")
    }

    func testUnpluggingTheWebcamSuggestsTheMacBookSetup() {
        let c = twoSetups()
        XCTAssertEqual(c.suggestedSetup(externalCameras: [], builtInCameras: ["MacBook Pro Camera"]), "MacBook")
    }

    func testTheSetupInUseIsKeptWhenItStillFits() {
        var c = twoSetups()
        c.activeSetupName = "Standing desk"
        XCTAssertEqual(c.suggestedSetup(externalCameras: ["HD Pro Webcam C920"], builtInCameras: []), "Standing desk")
    }

    func testNoCameraSuggestsNothing() {
        XCTAssertNil(twoSetups().suggestedSetup(externalCameras: [], builtInCameras: []))
    }

    // MARK: Calibration stays per camera

    func testCalibrationIsPerWebcamAndSharedByEverySetupUsingIt() {
        var c = twoSetups()
        c.setCalibration(WebcamCalibration(focalWidths: 0.7812, pitchDegrees: -2.5), forWebcam: "HD Pro Webcam C920")
        c.setCalibration(WebcamCalibration(focalWidths: 0.9), forWebcam: "MacBook Pro Camera")
        let r = DeskConfig(text: c.document.text)
        XCTAssertEqual(r.calibration(forWebcam: "HD Pro Webcam C920"), WebcamCalibration(focalWidths: 0.7812, pitchDegrees: -2.5))
        XCTAssertEqual(r.calibration(forWebcam: "MacBook Pro Camera").focalWidths, 0.9)
        XCTAssertEqual(r.calibration(forWebcam: "Other"), WebcamCalibration())
        var copy = r
        XCTAssertTrue(copy.duplicateSetup("Standing desk", as: "Standing desk 2"))
        XCTAssertEqual(copy.calibration(forWebcam: "HD Pro Webcam C920").focalWidths, 0.7812)
        XCTAssertTrue(copy.deleteSetup("Standing desk 2"))
        XCTAssertEqual(copy.calibration(forWebcam: "HD Pro Webcam C920").focalWidths, 0.7812, "deleting a setup keeps calibration")
    }

    func testUncalibratedWebcamFallsBackToATypicalFieldOfView() {
        let c = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertEqual(c.camera(forWebcam: "x", fieldOfViewDegrees: 90).focalWidths, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.camera(forWebcam: "x", fieldOfViewDegrees: nil).focalWidths, CameraModel(fieldOfViewDegrees: 70).focalWidths, accuracy: 0.001)
    }

    func testNonNumbersAndNonPositiveValuesCountAsNotMeasured() {
        let c = DeskConfig(text: "[setups.\"A\"]\nscreen_top_height_cm = \"tall\"\nlens_offset_cm = -3\nuser_height_cm = 180")
        let m = c.profile(named: "A").measurements
        XCTAssertNil(m.screenTopHeightCm)
        XCTAssertNil(m.lensOffsetCm)
        XCTAssertEqual(m.userHeightCm, 180)
    }

    func testWebcamNameWithQuotesRoundTrips() {
        var c = DeskConfig(text: "")
        c.setCalibration(WebcamCalibration(focalWidths: 0.8), forWebcam: "Cam \"Pro\" 2")
        XCTAssertEqual(DeskConfig(text: c.document.text).calibration(forWebcam: "Cam \"Pro\" 2").focalWidths, 0.8)
    }
}

final class TOMLLayoutTests: XCTestCase {
    func testMeasuredValueTakesTheCommentedTemplateLine() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.activeProfile
        p.measurements.screenTopHeightCm = 52
        c.save(p)
        let text = c.document.text
        XCTAssertTrue(text.contains("# Top edge of the screen above the desk surface (default 45; 24 for the built-in screen).\nscreen_top_height_cm = 52\n"))
        XCTAssertFalse(text.contains("# screen_top_height_cm"))
    }

    func testNewSectionsStayAfterTheirOwnIntroducingComment() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        c.setCalibration(WebcamCalibration(focalWidths: 0.8), forWebcam: "Cam")
        XCTAssertTrue(c.document.text.contains("# pitch_degrees = 0\n\n[webcams.\"Cam\"]\nfocal_widths = 0.8"))
    }
}
