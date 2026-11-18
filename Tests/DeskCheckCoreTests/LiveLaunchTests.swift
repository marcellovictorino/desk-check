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
        for text in ["deskcheck://settings", "deskcheck://live/extra", "https://live", "deskcheck:live", "otherapp://live"] {
            #expect(!LiveLink.isLive(URL(string: text)!), "\(text)")
        }
        #expect(LiveLink.isLive(LiveLink.live))
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
        #expect(KeyShortcut(" Ctrl + Option + L ") == KeyShortcut("control+alt+l"))
        let single = try #require(KeyShortcut("cmd+shift+1"))
        #expect(single.modifiers == KeyShortcut.command | KeyShortcut.shift)
        #expect(single.keyCode == 18)
    }

    @Test func combinationsThatWouldBreakTypingOrAreIncompleteAreRejected() {
        for text in ["z", "space", "hyper", "hyper+", "hyper+zz", "hyper+z+x", "hyper+f13", "", "+z"] {
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
        // Saving other settings keeps the line.
        var kept = config
        kept.autoSwitch = true
        #expect(kept.document.text.contains("live_shortcut = \"hyper+z\""))
    }
}
