import Foundation
import Testing
import DeskCheckCore
@testable import DeskCheck

/// Intent: a failed settings load must be visible and must not start a check using starter calibration.
@Suite struct SettingsStateTests {
    @MainActor
    @Test func failedLoadExposesWarningAndKeepsCameraOffUntilFileIsChosen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-warning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "desk-check-warning-tests.\(UUID().uuidString)"))
        let settings = SettingsFile(defaultFile: root.appendingPathComponent("missing.toml"), defaults: defaults)
        let checker = PostureChecker(settings: settings)
        #expect(checker.settingsWarning != nil)
        #expect(checker.setupNames.isEmpty)
        checker.check()
        #expect(!(checker.isRunning))
        #expect(checker.settingsWarning != nil)
        // Live must read this same failed fixture, never the global settings or the camera.
        checker.live.start()
        #expect(!(checker.live.isRunning))
        #expect(!(checker.live.awaitingPermission))
        #expect(checker.live.statusText == settings.loadWarning)
        let recovered = root.appendingPathComponent("recovered.toml")
        var config = DeskConfig(text: DeskConfig.starterContents)
        let renamed = config.renameSetup(config.activeSetupName, to: "Recovered desk")
        #expect(renamed)
        try config.document.text.write(to: recovered, atomically: false, encoding: .utf8)
        try settings.choose(recovered)
        checker.reloadSetups()
        #expect(checker.settingsWarning == nil)
        #expect(checker.setupNames == config.setupNames)
        #expect(checker.activeSetup == config.activeSetupName)
        #expect(!(checker.isRunning))
    }
}
