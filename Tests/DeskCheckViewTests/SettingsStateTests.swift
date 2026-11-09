import Foundation
import XCTest
import DeskCheckCore
@testable import DeskCheck

/// Intent: a failed settings load must be visible and must not start a check using starter calibration.
final class SettingsStateTests: XCTestCase {
    @MainActor
    func testFailedLoadExposesWarningAndKeepsCameraOffUntilFileIsChosen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-warning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "desk-check-warning-tests.\(UUID().uuidString)"))
        let settings = SettingsFile(defaultFile: root.appendingPathComponent("missing.toml"), defaults: defaults)
        let checker = PostureChecker(settings: settings)
        XCTAssertNotNil(checker.settingsWarning)
        XCTAssertTrue(checker.setupNames.isEmpty)
        checker.check()
        XCTAssertFalse(checker.isRunning)
        XCTAssertNotNil(checker.settingsWarning)
        let recovered = root.appendingPathComponent("recovered.toml")
        var config = DeskConfig(text: DeskConfig.starterContents)
        XCTAssertTrue(config.renameSetup(config.activeSetupName, to: "Recovered desk"))
        try config.document.text.write(to: recovered, atomically: false, encoding: .utf8)
        try settings.choose(recovered)
        checker.reloadSetups()
        XCTAssertNil(checker.settingsWarning)
        XCTAssertEqual(checker.setupNames, config.setupNames)
        XCTAssertEqual(checker.activeSetup, config.activeSetupName)
        XCTAssertFalse(checker.isRunning)
    }
}
