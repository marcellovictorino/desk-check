import Foundation

/// Where Desk Undo keeps its settings: `~/.config/desk-undo/config.toml`.
///
/// Inside the App Sandbox, `NSHomeDirectory()` and `FileManager.homeDirectoryForCurrentUser`
/// point at the app's container, not the person's home folder. The sandbox grants one
/// exception, `~/.config/desk-undo/`, so the path is built from the real home folder
/// read from the user database.
public enum ConfigLocation {
    public static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var directory: URL {
        realHomeDirectory.appendingPathComponent(".config/desk-undo", isDirectory: true)
    }

    public static var file: URL {
        directory.appendingPathComponent("config.toml")
    }

    /// Writes a commented starter file when none exists. Returns true when it wrote one.
    @discardableResult
    public static func ensureStarterFile() throws -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) { return false }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try starterContents.write(to: file, atomically: false, encoding: .utf8)
        return true
    }

    public static let starterContents = """
    # Desk Undo settings. Lines starting with # are comments.
    # Measurements and presets arrive in later versions; the app keeps only numbers here.

    """
}
