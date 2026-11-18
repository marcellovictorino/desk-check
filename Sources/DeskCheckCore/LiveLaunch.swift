import Foundation

/// The `deskcheck://live` link: the one way anything outside the app (the `desk-check live` command, a Raycast
/// quicklink, a Shortcuts action, the built-in key combination) asks Desk Check to open its panel and start Live.
public enum LiveLink {
    public static let scheme = "deskcheck"

    /// True for `deskcheck://live`, with or without a trailing slash, in any letter case. Anything else is ignored.
    public static func isLive(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "live" else { return false }
        return url.path.isEmpty || url.path == "/"
    }
}

/// A global key combination written in the settings file, such as `hyper+z` or `ctrl+opt+l`. Hyper is the Caps Lock
/// trick that Raycast and similar tools use: apps see Shift, Control, Option and Command held together.
/// The numbers are the ones Carbon's RegisterEventHotKey takes, so this stays free of any UI framework.
public struct KeyShortcut: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    private static let modifierWords: [String: UInt32] = [
        "hyper": command | shift | option | control,
        "cmd": command, "command": command,
        "shift": shift,
        "opt": option, "option": option, "alt": option,
        "ctrl": control, "control": control,
    ]

    /// Key codes for the letters, digits and space on every Mac keyboard layout's physical keys (ANSI positions).
    private static let keys: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49,
    ]

    /// Parses `modifier+modifier+key`. Returns nil for no modifier (a bare letter would steal typing everywhere),
    /// no key, more than one key or a word it does not know.
    public init?(_ text: String) {
        var modifiers: UInt32 = 0
        var key: UInt32?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            let word = part.trimmingCharacters(in: .whitespaces)
            if let m = Self.modifierWords[word] {
                modifiers |= m
            } else if let code = Self.keys[word], key == nil {
                key = code
            } else {
                return nil
            }
        }
        guard modifiers != 0, let key else { return nil }
        self.keyCode = key
        self.modifiers = modifiers
    }
}
