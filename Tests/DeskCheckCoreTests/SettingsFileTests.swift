import Foundation
import Testing

@testable import DeskCheckCore

/// Intent: the settings-file choice must preserve the default, remember access, and never save a failed-load fallback.
/// These filesystem tests exercise real TOML and bookmarks; native sandbox permission is checked separately in the app.
@Suite struct SettingsFileTests {
    private func fixture() throws -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, try #require(UserDefaults(suiteName: "desk-check-settings-tests.\(UUID().uuidString)")))
    }

    @Test func defaultLoadsAndSavesWithoutChangingCommentsOrCalibration() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        let store = SettingsFile(defaultFile: file, defaults: defaults) {
            try ConfigLocation.ensureStarterFile(in: root, legacy: root.appendingPathComponent("legacy"))
        }
        var config = try store.read()
        #expect(store.file == file)
        #expect(!(store.hasSelection))
        config.setCalibration(WebcamCalibration(focalWidths: 0.8, pitchDegrees: -8.35), forWebcam: "External camera")
        try store.save(config)
        let before = try String(contentsOf: file, encoding: .utf8)
        let renamed = config.renameSetup(config.activeSetupName, to: "Main desk")
        #expect(renamed)
        try store.save(config)
        let restored = try store.read()
        #expect(restored.activeSetupName == "Main desk")
        #expect(restored.calibration(forWebcam: "External camera") == config.calibration(forWebcam: "External camera"))
        let comments = before.components(separatedBy: .newlines).filter { $0.hasPrefix("#") }
        #expect(restored.document.text.components(separatedBy: .newlines).filter { $0.hasPrefix("#") } == comments)
    }

    @Test func choiceSurvivesNewStoreAndChangesWriteDestination() throws {
        let (root, defaults) = try fixture()
        let original = root.appendingPathComponent("default.toml")
        let selected = root.appendingPathComponent("dotfiles.toml")
        try DeskConfig.starterContents.write(to: original, atomically: false, encoding: .utf8)
        var chosen = DeskConfig(text: DeskConfig.starterContents)
        let renamed = chosen.renameSetup(chosen.activeSetupName, to: "External desk")
        #expect(renamed)
        try chosen.document.text.write(to: selected, atomically: false, encoding: .utf8)
        let store = SettingsFile(defaultFile: original, defaults: defaults)
        #expect(try store.choose(selected).activeSetupName == chosen.activeSetupName)
        let relaunched = SettingsFile(defaultFile: original, defaults: defaults)
        var config = try relaunched.read()
        #expect(config.activeSetupName == chosen.activeSetupName)
        let renamed2 = config.renameSetup(config.activeSetupName, to: "Renamed desk")
        #expect(renamed2)
        try relaunched.save(config)
        #expect(DeskConfig(text: try String(contentsOf: selected, encoding: .utf8)).activeSetupName == "Renamed desk")
        #expect(try String(contentsOf: original, encoding: .utf8) == DeskConfig.starterContents)
        _ = try relaunched.choose(original)
        #expect(try relaunched.read().activeSetupName == DeskConfig.defaultSetupName)
        #expect(relaunched.file.resolvingSymlinksInPath() == original.resolvingSymlinksInPath())
    }

    @Test func failedChoiceKeepsPreviousFileAndFailedLoadBlocksSavingUntilRecovery() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        try DeskConfig.starterContents.write(to: file, atomically: false, encoding: .utf8)
        let store = SettingsFile(defaultFile: file, defaults: defaults)
        _ = try store.choose(file)
        #expect(throws: (any Error).self) { try store.choose(root.appendingPathComponent("absent.toml")) }
        #expect(try store.read().document.text == DeskConfig.starterContents)
        // Real invalid UTF-8 makes a readable file fail to load, without deleting the original fixture.
        let unreadable = Data([0xff, 0xfe, 0xff])
        try unreadable.write(to: file)
        _ = store.load()
        #expect(store.loadWarning != nil)
        #expect(throws: (any Error).self) { try store.save(DeskConfig(text: DeskConfig.starterContents)) }
        #expect(try Data(contentsOf: file) == unreadable)
        // Restored access alone must not let a stale fallback form overwrite the recovered file.
        var original = DeskConfig(text: DeskConfig.starterContents)
        let renamed = original.renameSetup(original.activeSetupName, to: "Restored original")
        #expect(renamed)
        try original.document.text.write(to: file, atomically: false, encoding: .utf8)
        #expect(throws: (any Error).self) { try store.save(DeskConfig(text: DeskConfig.starterContents)) }
        #expect(try String(contentsOf: file, encoding: .utf8) == original.document.text)
        let recovered = root.appendingPathComponent("recovered.toml")
        try DeskConfig.starterContents.write(to: recovered, atomically: false, encoding: .utf8)
        _ = try store.choose(recovered)
        #expect(store.loadWarning == nil)
        try store.save(try store.read())
    }

    @Test func brokenBookmarkDoesNotFallBackToDefaultForSaving() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        try DeskConfig.starterContents.write(to: file, atomically: false, encoding: .utf8)
        let selected = root.appendingPathComponent("selected.toml")
        try DeskConfig.starterContents.write(to: selected, atomically: false, encoding: .utf8)
        let store = SettingsFile(defaultFile: file, defaults: defaults)
        try store.choose(selected)
        let location = store.file
        defaults.set(Data("invalid bookmark".utf8), forKey: "settingsFileBookmark")
        // Review defect: rendering the last loaded location must not resolve bookmarks or change preferences.
        #expect(store.file == location)
        _ = store.load()
        #expect(store.loadWarning != nil)
        #expect(throws: (any Error).self) { try store.save(DeskConfig(text: "")) }
        #expect(try String(contentsOf: file, encoding: .utf8) == DeskConfig.starterContents)
    }

    @Test func danglingDefaultSymlinkIsNotReplacedByStarterFile() throws {
        let (root, defaults) = try fixture()
        let file = root.appendingPathComponent("config.toml")
        let missing = root.appendingPathComponent("dotfiles/config.toml")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: missing)
        let store = SettingsFile(defaultFile: file, defaults: defaults) {
            try ConfigLocation.ensureStarterFile(in: root, legacy: root.appendingPathComponent("legacy"))
        }
        _ = store.load()
        #expect(store.loadWarning != nil)
        #expect(throws: (any Error).self) { try store.save(DeskConfig(text: DeskConfig.starterContents)) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.path) == missing.path)
        #expect(!(FileManager.default.fileExists(atPath: missing.path)))
    }

    /// Intent (bug report): a Stow-linked default the sandbox will not follow must name the real file
    /// and open the panel on it, so one Open click makes the settings work.
    @Test func linkedDefaultThatCannotBeReadNamesItsTargetAndOpensThePanelThere() throws {
        let (root, defaults) = try fixture()
        let stowed = root.appendingPathComponent("mac-nix-config/stow/desk-check/.config/desk-check", isDirectory: true)
        try FileManager.default.createDirectory(at: stowed, withIntermediateDirectories: true)
        let target = stowed.appendingPathComponent("config.toml")
        var config = DeskConfig(text: DeskConfig.starterContents)
        let renamed = config.renameSetup(config.activeSetupName, to: "Main Home")
        #expect(renamed)
        try config.document.text.write(to: target, atomically: false, encoding: .utf8)
        let home = root.appendingPathComponent(".config/desk-check", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let link = home.appendingPathComponent("config.toml")
        // Stow writes relative links.
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: "../../mac-nix-config/stow/desk-check/.config/desk-check/config.toml")
        let store = SettingsFile(defaultFile: link, defaults: defaults)
        #expect(store.panelStart.path == target.resolvingSymlinksInPath().path)

        // Stand-in for the sandbox refusing the link target: the same permission error the app reports.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path) }
        #expect(throws: (any Error).self) { try store.read() }
        let warning = try #require(store.loadWarning)
        #expect(warning.contains(target.resolvingSymlinksInPath().path), Comment(rawValue: warning))
        #expect(warning.contains("Choose settings file"), Comment(rawValue: warning))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        #expect(try store.choose(store.panelStart).activeSetupName == "Main Home")
        #expect(store.loadWarning == nil)
        #expect(store.panelStart.path == target.resolvingSymlinksInPath().path)
    }

    /// Intent: a link to a file that is gone must not claim the file only needs permission.
    @Test func danglingLinkedDefaultKeepsTheMissingFileWarning() throws {
        let (root, defaults) = try fixture()
        let link = root.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("gone.toml").path)
        let store = SettingsFile(defaultFile: link, defaults: defaults)
        #expect(throws: (any Error).self) { try store.read() }
        #expect(try #require(store.loadWarning).hasPrefix("Could not load settings:"))
    }

    /// Intent (review finding): a readable linked file that fails to load for another reason keeps its diagnosis,
    /// since choosing it and clicking Open cannot fix it.
    @Test func linkedDefaultWithUnreadableTextKeepsItsOwnDiagnosis() throws {
        let (root, defaults) = try fixture()
        let target = root.appendingPathComponent("stowed.toml")
        try Data([0x5B, 0xFF, 0xFE, 0x5D]).write(to: target)
        let link = root.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        let store = SettingsFile(defaultFile: link, defaults: defaults)
        #expect(throws: (any Error).self) { try store.read() }
        #expect(try #require(store.loadWarning).hasPrefix("Could not load settings:"))
    }
}
