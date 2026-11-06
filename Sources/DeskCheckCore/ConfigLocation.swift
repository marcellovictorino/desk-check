import Foundation

/// Where Desk Check keeps its settings: `~/.config/desk-check/config.toml`.
///
/// Inside the App Sandbox, `NSHomeDirectory()` and `FileManager.homeDirectoryForCurrentUser`
/// point at the app's container, not the person's home folder. The sandbox allows writes to
/// `~/.config/desk-check/` and reads from `~/.config/desk-undo/`, so the path is built from
/// the real home folder read from the user database.
public enum ConfigLocation {
    public static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Desk Check was called Desk Undo until version 0.2; its settings lived in `~/.config/desk-undo/`.
    /// The sandbox lets the app read that folder (see Resources/DeskCheck.entitlements) so a first launch can copy it.
    public static var legacyDirectory: URL {
        realHomeDirectory.appendingPathComponent(".config/desk-undo", isDirectory: true)
    }

    public static var directory: URL {
        realHomeDirectory.appendingPathComponent(".config/desk-check", isDirectory: true)
    }

    public static var file: URL {
        directory.appendingPathComponent("config.toml")
    }

    public static func load() -> DeskConfig {
        DeskConfig(text: (try? String(contentsOf: file, encoding: .utf8)) ?? DeskConfig.starterContents)
    }

    public static func save(_ config: DeskConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try config.document.text.write(to: file, atomically: false, encoding: .utf8)  // not atomic, so a config symlinked from dotfiles stays a symlink
    }

    /// Writes a commented starter file when none exists. Returns true when it wrote one.
    @discardableResult
    public static func ensureStarterFile() throws -> Bool {
        try ensureStarterFile(in: directory, legacy: legacyDirectory)
    }

    /// When `directory` has no `config.toml`, copies the one in `legacy` (the old Desk Undo folder, left untouched)
    /// or writes the starter file when no legacy file exists. A legacy read error is thrown so a later launch can retry.
    /// Returns true when it wrote a file that is not a copy of the old settings.
    @discardableResult
    static func ensureStarterFile(in directory: URL, legacy: URL) throws -> Bool {
        let fm = FileManager.default
        let target = directory.appendingPathComponent("config.toml")
        if fm.fileExists(atPath: target.path) { return false }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = legacy.appendingPathComponent("config.toml")
        do {
            let text = try String(contentsOf: old, encoding: .utf8)
            try text.write(to: target, atomically: false, encoding: .utf8)
            return false
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            try starterContents.write(to: target, atomically: false, encoding: .utf8)
        } catch {
            throw LegacyConfigReadError(underlying: error)
        }
        return true
    }

    public static let starterContents = DeskConfig.starterContents
}

private struct LegacyConfigReadError: LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        "Legacy settings exist but cannot be read: \(underlying.localizedDescription)"
    }
}
