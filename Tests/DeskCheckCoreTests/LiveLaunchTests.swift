import Foundation
import Testing

@testable import DeskCheckCore

/// Intent source: the captain's request to open Desk Check straight into Live from a command or a key combination such
/// as Hyper+Z (approved plan card): one `deskcheck://live` link, and a `live_shortcut` line in config.toml.
@Suite struct LiveLaunchTests {
    @Test func theLiveLinkIsRecognisedAndNothingElseIs() {
        for text in ["deskcheck://live", "deskcheck://live/", "DeskCheck://LIVE"] {
            #expect(LiveLink.isLive(URL(string: text)!), "\(text)")
        }
        for text in ["deskcheck://settings", "deskcheck://live/extra", "https://live", "deskcheck:live"] {
            #expect(!LiveLink.isLive(URL(string: text)!), "\(text)")
        }
    }

    /// Raycast's Caps Lock Hyper key reaches apps as Shift, Control, Option and Command held together.
    @Test func hyperMeansAllFourModifiers() throws {
        let hyper = try #require(KeyShortcut("hyper+z"))
        #expect(hyper.modifiers == KeyShortcut.command | KeyShortcut.shift | KeyShortcut.option | KeyShortcut.control)
        #expect(hyper.keyCode == 6)  // the physical Z key
        let spelledOut = try #require(KeyShortcut("cmd+ctrl+opt+shift+z"))
        #expect(spelledOut == hyper)
    }

    @Test func modifierNamesCaseAndSpacingAreForgiving() throws {
        for text in [" Ctrl + Option + L ", "control+alt+l"] {
            let shortcut = try #require(KeyShortcut(text), "\(text)")
            #expect(shortcut.modifiers == KeyShortcut.control | KeyShortcut.option)
            #expect(shortcut.keyCode == 37)  // the physical L key
        }
        let single = try #require(KeyShortcut("cmd+shift+1"))
        #expect(single.modifiers == KeyShortcut.command | KeyShortcut.shift)
        #expect(single.keyCode == 18)
    }

    @Test func combinationsThatWouldBreakTypingOrAreIncompleteAreRejected() {
        for text in ["z", "space", "hyper", "hyper+zz", "hyper+z+x", "hyper+f13", ""] {
            #expect(KeyShortcut(text) == nil, "\(text)")
        }
    }

    @Test func theSettingsFileLineIsReadAndAbsenceIsFine() throws {
        #expect(DeskConfig(text: DeskConfig.starterContents).liveShortcut == nil)  // only a comment in the starter file
        let config = DeskConfig(text: "[preferences]\nlive_shortcut = \"hyper+z\"\n")
        #expect(config.liveShortcutText == "hyper+z")
        #expect(config.liveShortcut == KeyShortcut("hyper+z"))
        let bad = DeskConfig(text: "[preferences]\nlive_shortcut = \"banana\"\n")
        #expect(bad.liveShortcutText == "banana")
        #expect(bad.liveShortcut == nil)
    }

    /// Saving another preference must not drop the shortcut line the person wrote.
    @Test func savingOtherSettingsKeepsTheShortcutLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-shortcut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("config.toml")
        try "[preferences]\n# my keys\nlive_shortcut = \"hyper+z\"\n".write(to: file, atomically: false, encoding: .utf8)
        let defaults = try #require(UserDefaults(suiteName: "desk-check-shortcut-tests.\(UUID().uuidString)"))
        let store = SettingsFile(defaultFile: file, defaults: defaults)
        var config = try store.read()
        config.autoSwitch = true
        try store.save(config)
        let reread = try store.read()
        #expect(reread.autoSwitch)
        #expect(reread.liveShortcut == KeyShortcut("hyper+z"))
        #expect(reread.document.text.contains("# my keys"))
    }
}
