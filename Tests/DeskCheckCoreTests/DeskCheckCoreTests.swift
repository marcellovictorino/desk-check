import Foundation
import Testing
@testable import DeskCheckCore

/// Intent sources: the piece 2 brief (SCR-705) asks for distance and height readings within
/// 3 cm and 2 cm, tape-measure inputs with defaults until measured, per-webcam calibration,
/// one sentence of advice with a number per adjustment, and a config file that allows comments.
@Suite struct GeometryTests {
    /// A Logitech C920 frame, 1920 x 1080, with a person 62 cm away whose eyes sit 4 cm above the lens axis.
    /// The pixel numbers come from the pinhole model for a 70.4 degree field of view; the A/B desk test
    /// with a real webcam is the check against the real world.
    let camera = CameraModel(fieldOfViewDegrees: 70.4)
    func eyes(span: Double, midY: Double, yaw: Double = 0) -> EyePoints {
        EyePoints(left: .init(x: 960 - span / 2, y: midY), right: .init(x: 960 + span / 2, y: midY),
                  imageWidth: 1920, imageHeight: 1080, yaw: yaw)
    }

    @Test func distanceAndHeightFromEyePoints() throws {
        let focalPx = camera.focalWidths * 1920
        let span = focalPx * 6.3 / 62
        let midY = 540 + focalPx * (4.0 / 62)
        let r = try #require(Geometry.reading(eyes(span: span, midY: midY), camera: camera,
                                               setup: Setup(screenTopHeightCm: 50, lensOffsetCm: 1.5)))
        #expect(abs((r.distanceCm) - (62)) <= 0.1)
        #expect(abs((r.eyeAboveScreenTopCm) - (5.5)) <= 0.2)   // 1.5 lens offset + 4 above the lens
        #expect(abs((r.eyeHeightAboveDeskCm) - (55.5)) <= 0.2)
    }

    @Test func movingTheScreen5cmChangesTheReadingBy5cm() throws {
        let focalPx = camera.focalWidths * 1920
        func read(_ d: Double) -> Double {
            Geometry.reading(eyes(span: focalPx * 6.3 / d, midY: 540), camera: camera, setup: Setup())!.distanceCm
        }
        #expect(abs((read(67) - read(62)) - (5)) <= 0.1)
    }

    @Test func turnedHeadDoesNotReadAsFarther() throws {
        let focalPx = camera.focalWidths * 1920
        let yaw = 0.35
        let span = focalPx * 6.3 / 60 * cos(yaw)
        let r = try #require(Geometry.reading(eyes(span: span, midY: 540, yaw: yaw), camera: camera, setup: Setup()))
        #expect(abs((r.distanceCm) - (60)) <= 0.1)
    }

    @Test func focalCalibrationFixesAWrongFieldOfView() throws {
        // The real lens is 78 degrees wide but the default assumes 65.
        let real = CameraModel(fieldOfViewDegrees: 78)
        let span = real.focalWidths * 1920 * 6.3 / 55           // person sits 55 cm away by tape
        let frame = eyes(span: span, midY: 540)
        let before = try #require(Geometry.reading(frame, camera: CameraModel(fieldOfViewDegrees: 60), setup: Setup()))
        #expect(abs(before.distanceCm - 55) > 3, "uncalibrated reading is off by more than the limit")
        let focal = try #require(Geometry.calibrateFocal(frame, tapeDistanceCm: 55))
        let after = try #require(Geometry.reading(frame, camera: CameraModel(focalWidths: focal), setup: Setup()))
        #expect(abs((after.distanceCm) - (55)) <= 0.1)
        // And the calibrated camera reads a different distance correctly.
        let moved = eyes(span: real.focalWidths * 1920 * 6.3 / 70, midY: 540)
        let reading = try #require(Geometry.reading(moved, camera: CameraModel(focalWidths: focal), setup: Setup()))
        #expect(abs((reading.distanceCm) - (70)) <= 0.1)
    }

    @Test func pitchCalibrationRecoversTiltedLens() throws {
        // Lens tilted up 6 degrees; eyes truly 3 cm above the lens axis height... measure at 60 cm.
        let tilt = 6.0 * .pi / 180
        let focalPx = camera.focalWidths * 1920
        let trueAngle = atan(8.0 / 60)                      // eyes 8 cm above the lens
        let midY = 540 + focalPx * tan(trueAngle - tilt)    // a lens tilted up sees the eyes lower
        let frame = eyes(span: focalPx * 6.3 / 60, midY: midY)
        let pitch = try #require(Geometry.calibratePitch(frame, focalWidths: camera.focalWidths, tapeDistanceCm: 60,
                                                         lensHeightAboveDeskCm: 40, eyeHeightAboveDeskCm: 48))
        #expect(abs((pitch) - (tilt)) <= 0.002)
        let r = try #require(Geometry.reading(frame, camera: CameraModel(focalWidths: camera.focalWidths, pitch: pitch),
                                               setup: Setup(screenTopHeightCm: 39, lensOffsetCm: 1)))
        #expect(abs((r.eyeHeightAboveDeskCm) - (48)) <= 0.3)
    }

    @Test func medianIgnoresOneBadFrame() {
        let good = PostureReading(distanceCm: 60, eyeAboveScreenTopCm: 4, eyeHeightAboveDeskCm: 50)
        let bad = PostureReading(distanceCm: 120, eyeAboveScreenTopCm: -30, eyeHeightAboveDeskCm: 10)
        #expect(Geometry.median([good, good, bad, good, good])?.distanceCm == 60)
    }

    @Test func noReadingWithoutEyes() {
        #expect(Geometry.reading(eyes(span: 0, midY: 540), camera: camera, setup: Setup()) == nil)
    }
}

@Suite struct AdviceTests {
    func reading(_ d: Double, _ h: Double) -> PostureReading {
        PostureReading(distanceCm: d, eyeAboveScreenTopCm: h, eyeHeightAboveDeskCm: 0)
    }

    @Test func eachAdjustmentGetsOneSentenceWithANumber() {
        let advice = AdviceEngine.advise(reading(45, 15))
        #expect(advice.map(\.sentence) == [
            "Distance: move the screen 15 cm further away.",
            "Screen: raise 10 cm.",
        ])
    }

    @Test func tooFarAndScreenTooHigh() {
        let advice = AdviceEngine.advise(reading(80, -3))
        #expect(advice[0].sentence == "Distance: move the screen 20 cm closer.")
        #expect(advice[1].sentence == "Screen: lower 8 cm.")
    }

    @Test func goodPostureNeedsNoAdjustment() {
        let advice = AdviceEngine.advise(reading(62, 4))
        #expect(advice.map(\.status) == [.good, .good])
    }
}

@Suite struct ConfigTests {
    @Test func starterFileHasOneStandingDeskSetupWithDefaults() {
        let c = DeskConfig(text: DeskConfig.starterContents)
        #expect(c.setupNames == ["Standing desk"])
        #expect(c.activeSetupName == "Standing desk")
        let p = c.activeProfile
        #expect(p.camera == .auto)
        #expect(p.measurements.screenTop == 45)
        #expect(p.supportsStandingPreset)
        #expect(!(c.showPreview))
        #expect(!(c.autoSwitch))
    }

    @Test func aFileWithNoSetupsShowsADefaultSetup() {
        let c = DeskConfig(text: "# old file\n[preferences]\npreview = true\n")
        #expect(c.setupNames == ["Standing desk"])
    }

    @Test func measuredValuesReplaceDefaultsAndSurviveASave() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.activeProfile
        p.measurements = Setup(screenDistanceCm: 58.5, screenTopHeightCm: 47, lensOffsetCm: 2, userHeightCm: 181, seatedEyeHeightCm: 41)
        c.save(p)
        let reread = DeskConfig(text: c.document.text).activeProfile
        #expect(reread.measurements == p.measurements)
        #expect(c.document.text.contains("# Delete a measurement line to go back to the default estimate"))
    }

    @Test func handWrittenCommentsAndOtherKeysSurviveAnEdit() {
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
        #expect(c.document.text.contains("# my own note"))
        #expect(c.document.text.contains("screen_top_height_cm = 50 # tape, Monday"))
        #expect(c.document.text.contains("custom_key = \"keep me\""))
        #expect(c.profile(named: "Desk").measurements.lensOffsetCm == 2)
        #expect(c.showPreview)
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
        let outcome1 = c.addSetup(mac)
        #expect(outcome1)
        return c
    }

    @Test func twoSetupsKeepTheirOwnCameraScreenAndMeasurements() {
        let c = DeskConfig(text: twoSetups().document.text)
        #expect(c.setupNames == ["Standing desk", "MacBook"])
        let desk = c.profile(named: "Standing desk"), mac = c.profile(named: "MacBook")
        #expect(desk.camera == .named("HD Pro Webcam C920"))
        #expect(desk.measurements.screenTopHeightCm == 50)
        #expect(mac.camera == .builtIn)
        #expect(mac.screen == "MacBook")
        #expect(mac.measurements.screenTopHeightCm == 22)
        #expect(mac.measurements.lensOffset == 0.5, "built-in camera defaults apply until measured")
        #expect(desk.measurements.lensOffset == 2)
    }

    @Test func seatedOnlySetupHasNoStandingPresetAndFixedAdjustments() {
        let c = DeskConfig(text: twoSetups().document.text)
        let mac = c.profile(named: "MacBook")
        #expect(!(mac.supportsStandingPreset))
        #expect(mac.fixed == [.deskHeight, .screenHeight])
        #expect(c.profile(named: "Standing desk").supportsStandingPreset)
        #expect(c.document.text.contains("desk_height = \"fixed\""))
    }

    @Test func fixedAdjustmentIsReportedNotAdvised() {
        let r = PostureReading(distanceCm: 45, eyeAboveScreenTopCm: 15, eyeHeightAboveDeskCm: 0)
        let advice = AdviceEngine.advise(r, fixed: [.screenHeight])
        #expect(advice[0].status == .adjust)
        #expect(advice[1].status == .fixed)
        #expect(advice[1].sentence == "Screen height is fixed in this setup; your eyes are 15 cm above its top edge.")
    }

    @Test func lastUsedSetupIsRemembered() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        #expect(DeskConfig(text: c.document.text).activeSetupName == "MacBook")
        c.activeSetupName = "Gone"   // a setup that no longer exists falls back to the first
        #expect(DeskConfig(text: c.document.text).activeSetupName == "Standing desk")
    }

    @Test func renameDuplicateAndDelete() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        let outcome2 = c.renameSetup("MacBook", to: "Sofa")
        #expect(outcome2)
        #expect(c.activeSetupName == "Sofa", "renaming the active setup keeps it active")
        #expect(c.profile(named: "Sofa").camera == .builtIn)
        let duplicated1 = c.duplicateSetup("Standing desk", as: "Standing desk 2")
        #expect(duplicated1)
        #expect(c.setupNames == ["Standing desk", "Standing desk 2", "Sofa"])
        #expect(c.profile(named: "Standing desk 2") == SetupProfile(name: "Standing desk 2", camera: .named("HD Pro Webcam C920"), screen: "external", measurements: c.profile(named: "Standing desk").measurements))
        let outcome3 = c.deleteSetup("Sofa")
        #expect(outcome3)
        #expect(c.activeSetupName == "Standing desk")
        #expect(c.setupNames == ["Standing desk", "Standing desk 2"])
        let outcome4 = c.deleteSetup("Standing desk 2")
        #expect(outcome4)
        let outcome5 = c.deleteSetup("Standing desk")
        #expect(!(outcome5), "the last setup stays")
    }

    @Test func namesMustBeNewAndNotEmpty() {
        var c = twoSetups()
        let outcome6 = c.addSetup(.external(name: ""))
        #expect(!(outcome6))
        let outcome7 = c.addSetup(.external(name: "MacBook"))
        #expect(!(outcome7))
        let outcome8 = c.renameSetup("MacBook", to: "Standing desk")
        #expect(!(outcome8))
        let duplicated2 = c.duplicateSetup("MacBook", as: " ")
        #expect(!(duplicated2))
        #expect(c.setupNames.count == 2)
    }

    @Test func setupNameWithQuotesAndDotsRoundTrips() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        let outcome9 = c.addSetup(.laptop(name: "Mum's \"sofa\" v1.2"))
        #expect(outcome9)
        #expect(DeskConfig(text: c.document.text).setupNames == ["Standing desk", "Mum's \"sofa\" v1.2"])
    }

    @Test func duplicateKeepsCommentsOfTheCopiedSetup() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        let duplicated3 = c.duplicateSetup("Standing desk", as: "Copy")
        #expect(duplicated3)
        #expect(c.document.text.components(separatedBy: "# Top edge of the screen above the desk surface").count - 1 == 2)
    }

    // MARK: Auto-suggest

    @Test func externalWebcamPluggedInSuggestsTheStandingDeskSetup() {
        var c = twoSetups()
        c.activeSetupName = "MacBook"
        #expect(c.suggestedSetup(externalCameras: ["HD Pro Webcam C920"], builtInCameras: ["MacBook Pro Camera"]) == "Standing desk")
    }

    @Test func unpluggingTheWebcamSuggestsTheMacBookSetup() {
        let c = twoSetups()
        #expect(c.suggestedSetup(externalCameras: [], builtInCameras: ["MacBook Pro Camera"]) == "MacBook")
    }

    @Test func theSetupInUseIsKeptWhenItStillFits() {
        var c = twoSetups()
        c.activeSetupName = "Standing desk"
        #expect(c.suggestedSetup(externalCameras: ["HD Pro Webcam C920"], builtInCameras: []) == "Standing desk")
    }

    @Test func noCameraSuggestsNothing() {
        #expect(twoSetups().suggestedSetup(externalCameras: [], builtInCameras: []) == nil)
    }

    // MARK: Calibration stays per camera

    @Test func calibrationIsPerWebcamAndSharedByEverySetupUsingIt() {
        var c = twoSetups()
        c.setCalibration(WebcamCalibration(focalWidths: 0.7812, pitchDegrees: -2.5), forWebcam: "HD Pro Webcam C920")
        c.setCalibration(WebcamCalibration(focalWidths: 0.9), forWebcam: "MacBook Pro Camera")
        let r = DeskConfig(text: c.document.text)
        #expect(r.calibration(forWebcam: "HD Pro Webcam C920") == WebcamCalibration(focalWidths: 0.7812, pitchDegrees: -2.5))
        #expect(r.calibration(forWebcam: "MacBook Pro Camera").focalWidths == 0.9)
        #expect(r.calibration(forWebcam: "Other") == WebcamCalibration())
        var copy = r
        let duplicated4 = copy.duplicateSetup("Standing desk", as: "Standing desk 2")
        #expect(duplicated4)
        #expect(copy.calibration(forWebcam: "HD Pro Webcam C920").focalWidths == 0.7812)
        let outcome10 = copy.deleteSetup("Standing desk 2")
        #expect(outcome10)
        #expect(copy.calibration(forWebcam: "HD Pro Webcam C920").focalWidths == 0.7812, "deleting a setup keeps calibration")
    }

    @Test func uncalibratedWebcamFallsBackToATypicalFieldOfView() {
        let c = DeskConfig(text: DeskConfig.starterContents)
        #expect(abs((c.camera(forWebcam: "x", fieldOfViewDegrees: 90).focalWidths) - (0.5)) <= 0.001)
        #expect(abs((c.camera(forWebcam: "x", fieldOfViewDegrees: nil).focalWidths) - (CameraModel(fieldOfViewDegrees: 70).focalWidths)) <= 0.001)
    }

    @Test func nonNumbersAndNonPositiveValuesCountAsNotMeasured() {
        let c = DeskConfig(text: "[setups.\"A\"]\nscreen_top_height_cm = \"tall\"\nlens_offset_cm = -3\nuser_height_cm = 180")
        let m = c.profile(named: "A").measurements
        #expect(m.screenTopHeightCm == nil)
        #expect(m.lensOffsetCm == nil)
        #expect(m.userHeightCm == 180)
    }

    @Test func webcamNameWithQuotesRoundTrips() {
        var c = DeskConfig(text: "")
        c.setCalibration(WebcamCalibration(focalWidths: 0.8), forWebcam: "Cam \"Pro\" 2")
        #expect(DeskConfig(text: c.document.text).calibration(forWebcam: "Cam \"Pro\" 2").focalWidths == 0.8)
    }
}

@Suite struct TOMLLayoutTests {
    @Test func measuredValueTakesTheCommentedTemplateLine() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.activeProfile
        p.measurements.screenTopHeightCm = 52
        c.save(p)
        let text = c.document.text
        #expect(text.contains("# Top edge of the screen above the desk surface (default 45; 24 for the built-in screen).\nscreen_top_height_cm = 52\n"))
        #expect(!(text.contains("# screen_top_height_cm")))
    }

    @Test func newSectionsStayAfterTheirOwnIntroducingComment() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        c.setCalibration(WebcamCalibration(focalWidths: 0.8), forWebcam: "Cam")
        #expect(c.document.text.contains("# pitch_degrees = 0\n\n[webcams.\"Cam\"]\nfocal_widths = 0.8"))
    }
}

/// Intent source: the Desk Check rename requires existing Desk Undo settings to carry over,
/// so users keep their setups, tape measurements and webcam calibration.
@Suite struct ConfigMigrationTests {
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    @Test func oldSettingsAreCopiedAndLeftInPlace() throws {
        let root = try scratch()
        let old = root.appendingPathComponent("desk-undo"), new = root.appendingPathComponent("desk-check")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        var legacyConfig = DeskConfig(text: DeskConfig.starterContents)
        legacyConfig.autoSwitch = true
        let legacyText = legacyConfig.document.text
        try legacyText.write(to: old.appendingPathComponent("config.toml"), atomically: false, encoding: .utf8)
        #expect(!(try ConfigLocation.ensureStarterFile(in: new, legacy: old)))
        #expect(try String(contentsOf: new.appendingPathComponent("config.toml"), encoding: .utf8) == legacyText)
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("config.toml").path))
    }

    @Test func newSettingsAreNeverOverwrittenByOldOnes() throws {
        let root = try scratch()
        let old = root.appendingPathComponent("desk-undo"), new = root.appendingPathComponent("desk-check")
        let oldConfig = DeskConfig(text: DeskConfig.starterContents)
        var newConfig = DeskConfig(text: DeskConfig.starterContents)
        newConfig.autoSwitch = true
        for (dir, config) in [(old, oldConfig), (new, newConfig)] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try config.document.text.write(to: dir.appendingPathComponent("config.toml"), atomically: false, encoding: .utf8)
        }
        try ConfigLocation.ensureStarterFile(in: new, legacy: old)
        #expect(try String(contentsOf: new.appendingPathComponent("config.toml"), encoding: .utf8) == newConfig.document.text)
    }

    @Test func noOldSettingsWritesTheStarterFile() throws {
        let root = try scratch()
        let new = root.appendingPathComponent("desk-check")
        #expect(try ConfigLocation.ensureStarterFile(in: new, legacy: root.appendingPathComponent("desk-undo")))
        #expect(try String(contentsOf: new.appendingPathComponent("config.toml"), encoding: .utf8) == DeskConfig.starterContents)
    }

    /// Intent source: the captain asked Desk Check to retry rather than replace unreadable legacy settings.
    @Test func unreadableLegacySettingsAreNotReplacedByStarterFile() throws {
        let root = try scratch()
        let old = root.appendingPathComponent("desk-undo"), new = root.appendingPathComponent("desk-check")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let oldFile = old.appendingPathComponent("config.toml")
        try DeskConfig.starterContents.write(to: oldFile, atomically: false, encoding: .utf8)
        let fm = FileManager.default
        let originalPermissions = try fm.attributesOfItem(atPath: oldFile.path)[.posixPermissions] as? NSNumber
        defer {
            if let originalPermissions {
                try? fm.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: oldFile.path)
            }
        }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: oldFile.path)

        #expect(performing: { try ConfigLocation.ensureStarterFile(in: new, legacy: old) }, throws: { error in
            error.localizedDescription.contains("Legacy settings exist but cannot be read")
        })
        #expect(!(fm.fileExists(atPath: new.appendingPathComponent("config.toml").path)))
    }
}
