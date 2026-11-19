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
        // An absent line means the default, so a new install works without editing the file.
        #expect(DeskConfig(text: DeskConfig.starterContents).liveShortcut == KeyShortcut("hyper+w"))
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

    /// The captain chose hyper+w as the default and an empty string as the way to switch it off.
    @Test func anEmptyLineMeansOffAndAbsentMeansTheDefault() {
        let off = DeskConfig(text: "[preferences]\nlive_shortcut = \"\"\n")
        #expect(off.liveShortcutText == nil)
        #expect(off.liveShortcut == nil)
        #expect(DeskConfig(text: "").liveShortcutText == "hyper+w")
    }

    /// The recorder reads a key code and the held modifiers; what it writes must read back as the same shortcut.
    @Test func aRecordedKeyWritesTextThatParsesBack() throws {
        let hyper = KeyShortcut.command | KeyShortcut.shift | KeyShortcut.option | KeyShortcut.control
        let recorded = try #require(KeyShortcut(keyCode: 13, modifiers: hyper))
        #expect(recorded.text == "hyper+w")
        #expect(recorded.symbol == "⌃⌥⇧⌘W")
        for (code, mods, text) in [
            (UInt32(37), KeyShortcut.control | KeyShortcut.option, "ctrl+opt+l"),
            (UInt32(49), KeyShortcut.command | KeyShortcut.shift, "cmd+shift+space"),
            (UInt32(18), KeyShortcut.command, "cmd+1"),
        ] {
            let shortcut = try #require(KeyShortcut(keyCode: code, modifiers: mods))
            #expect(shortcut.text == text)
            #expect(KeyShortcut(shortcut.text) == shortcut)
        }
    }

    /// Caps Lock and Fn must not change the shortcut, a bare key would steal typing, and keys the file cannot
    /// hold (arrows, F-keys, Return) are refused.
    @Test func theRecorderIgnoresStrayModifiersAndRefusesWhatTheFileCannotHold() throws {
        let capsLockAndFn: UInt32 = 0x10000 | 0x800000
        let withStray = try #require(KeyShortcut(keyCode: 13, modifiers: KeyShortcut.control | capsLockAndFn))
        #expect(withStray == KeyShortcut("ctrl+w"))
        #expect(KeyShortcut(keyCode: 13, modifiers: capsLockAndFn) == nil)
        #expect(KeyShortcut(keyCode: 13, modifiers: 0) == nil)
        for code: UInt32 in [36, 123, 122, 53] {  // Return, left arrow, F1, Esc
            #expect(KeyShortcut(keyCode: code, modifiers: KeyShortcut.command) == nil, "\(code)")
        }
    }

    /// Recording writes at once into the file, keeps the person's comments, and "off" survives a reload.
    @Test func settingTheShortcutRewritesOnlyItsLine() throws {
        var config = DeskConfig(text: "[preferences]\n# my keys\nlive_shortcut = \"hyper+z\" # old\nauto_switch = true\n")
        let new = try #require(KeyShortcut("ctrl+opt+l"))
        config.setLiveShortcut(new)
        #expect(DeskConfig(text: config.document.text).liveShortcut == new)
        #expect(config.document.text.contains("# my keys"))
        #expect(config.autoSwitch)
        config.setLiveShortcut(nil)
        let reread = DeskConfig(text: config.document.text)
        #expect(reread.liveShortcutText == nil)
        // Without a recorded line the starter file's comment becomes the real line.
        var starter = DeskConfig(text: DeskConfig.starterContents)
        starter.setLiveShortcut(new)
        #expect(starter.document.text.contains("\nlive_shortcut = \"ctrl+opt+l\""))
        #expect(!starter.document.text.contains("# live_shortcut"))
    }
}
