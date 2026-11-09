import XCTest
@testable import DeskCheckCore

/// Intent: the settings-file choice must preserve the default, remember access, and never save a failed-load fallback.
/// These filesystem tests exercise real TOML and bookmarks; native sandbox permission is checked separately in the app.
final class SettingsFileTests: XCTestCase {
    private func fixture() throws -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, try XCTUnwrap(UserDefaults(suiteName: "desk-check-settings-tests.\(UUID().uuidString)")))
    }

    func testDefaultLoadsAndSavesWithoutChangingCommentsOrCalibration() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        let store = SettingsFile(defaultFile: file, defaults: defaults) {
            try ConfigLocation.ensureStarterFile(in: root, legacy: root.appendingPathComponent("legacy"))
        }
        var config = try store.read()
        XCTAssertEqual(store.file, file)
        XCTAssertFalse(store.hasSelection)
        config.setCalibration(WebcamCalibration(focalWidths: 0.8, pitchDegrees: -8.35), forWebcam: "External camera")
        try store.save(config)
        let before = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(config.renameSetup(config.activeSetupName, to: "Main desk"))
        try store.save(config)
        let restored = try store.read()
        XCTAssertEqual(restored.activeSetupName, "Main desk")
        XCTAssertEqual(restored.calibration(forWebcam: "External camera"), config.calibration(forWebcam: "External camera"))
        let comments = before.components(separatedBy: .newlines).filter { $0.hasPrefix("#") }
        XCTAssertEqual(restored.document.text.components(separatedBy: .newlines).filter { $0.hasPrefix("#") }, comments)
    }

    func testChoiceSurvivesNewStoreAndChangesWriteDestination() throws {
        let (root, defaults) = try fixture()
        let original = root.appendingPathComponent("default.toml")
        let selected = root.appendingPathComponent("dotfiles.toml")
        try DeskConfig.starterContents.write(to: original, atomically: false, encoding: .utf8)
        var chosen = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertTrue(chosen.renameSetup(chosen.activeSetupName, to: "External desk"))
        try chosen.document.text.write(to: selected, atomically: false, encoding: .utf8)
        let store = SettingsFile(defaultFile: original, defaults: defaults)
        XCTAssertEqual(try store.choose(selected).activeSetupName, chosen.activeSetupName)
        let relaunched = SettingsFile(defaultFile: original, defaults: defaults)
        var config = try relaunched.read()
        XCTAssertEqual(config.activeSetupName, chosen.activeSetupName)
        XCTAssertTrue(config.renameSetup(config.activeSetupName, to: "Renamed desk"))
        try relaunched.save(config)
        XCTAssertEqual(DeskConfig(text: try String(contentsOf: selected, encoding: .utf8)).activeSetupName, "Renamed desk")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), DeskConfig.starterContents)
        _ = try relaunched.choose(original)
        XCTAssertEqual(try relaunched.read().activeSetupName, DeskConfig.defaultSetupName)
        XCTAssertEqual(relaunched.file.resolvingSymlinksInPath(), original.resolvingSymlinksInPath())
    }

    func testFailedChoiceKeepsPreviousFileAndFailedLoadBlocksSavingUntilRecovery() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        try DeskConfig.starterContents.write(to: file, atomically: false, encoding: .utf8)
        let store = SettingsFile(defaultFile: file, defaults: defaults)
        _ = try store.choose(file)
        XCTAssertThrowsError(try store.choose(root.appendingPathComponent("absent.toml")))
        XCTAssertEqual(try store.read().document.text, DeskConfig.starterContents)
        // Real invalid UTF-8 makes a readable file fail to load, without deleting the original fixture.
        let unreadable = Data([0xff, 0xfe, 0xff])
        try unreadable.write(to: file)
        _ = store.load()
        XCTAssertNotNil(store.loadWarning)
        XCTAssertThrowsError(try store.save(DeskConfig(text: DeskConfig.starterContents)))
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
        // Restored access alone must not let a stale fallback form overwrite the recovered file.
        var original = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertTrue(original.renameSetup(original.activeSetupName, to: "Restored original"))
        try original.document.text.write(to: file, atomically: false, encoding: .utf8)
        XCTAssertThrowsError(try store.save(DeskConfig(text: DeskConfig.starterContents)))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original.document.text)
        let recovered = root.appendingPathComponent("recovered.toml")
        try DeskConfig.starterContents.write(to: recovered, atomically: false, encoding: .utf8)
        _ = try store.choose(recovered)
        XCTAssertNil(store.loadWarning)
        try store.save(try store.read())
    }

    func testBrokenBookmarkDoesNotFallBackToDefaultForSaving() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        try DeskConfig.starterContents.write(to: file, atomically: false, encoding: .utf8)
        defaults.set(Data("invalid bookmark".utf8), forKey: "settingsFileBookmark")
        let store = SettingsFile(defaultFile: file, defaults: defaults)
        _ = store.load()
        XCTAssertNotNil(store.loadWarning)
        XCTAssertThrowsError(try store.save(DeskConfig(text: "")))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), DeskConfig.starterContents)
    }

    func testDanglingDefaultSymlinkIsNotReplacedByStarterFile() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        let missing = root.appendingPathComponent("dotfiles/config.toml")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: missing)
        let store = SettingsFile(defaultFile: file, defaults: defaults) {
            try ConfigLocation.ensureStarterFile(in: root, legacy: root.appendingPathComponent("legacy"))
        }
        _ = store.load()
        XCTAssertNotNil(store.loadWarning)
        XCTAssertThrowsError(try store.save(DeskConfig(text: DeskConfig.starterContents)))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), missing.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
}
