import Foundation

/// Owns a file choice and its sandbox permission. All reads and writes resolve the same bookmark.
/// A failed load never authorises saving the starter configuration over the original file.
public final class SettingsFile {
    private let defaults: UserDefaults
    private let defaultFile: URL
    private let prepareDefault: () throws -> Void
    private static let bookmarkKey = "settingsFileBookmark"
    public private(set) var loadWarning: String?
    /// Last resolved location for display. Reading this property performs no bookmark or preference work.
    public private(set) var file: URL
    private var loaded = false

    public init(defaultFile: URL, defaults: UserDefaults, prepareDefault: @escaping () throws -> Void = {}) {
        self.defaultFile = defaultFile
        self.file = defaultFile
        self.defaults = defaults
        self.prepareDefault = prepareDefault
    }

    public var hasSelection: Bool { defaults.object(forKey: Self.bookmarkKey) != nil }

    public func read() throws -> DeskConfig {
        do {
            if !hasSelection { try prepareDefault() }
            let location = try resolve()
            file = location
            let config = try access(location) { DeskConfig(text: try String(contentsOf: $0, encoding: .utf8)) }
            loaded = true
            loadWarning = nil
            return config
        } catch {
            loaded = false
            loadWarning = "Could not load settings: \(error.localizedDescription) Choose your settings file in Settings. Saving and camera checks are unavailable until settings load."
            throw error
        }
    }

    /// Kept for views that need a shape to render while the warning explains that settings are unavailable.
    public func load() -> DeskConfig {
        (try? read()) ?? DeskConfig(text: DeskConfig.starterContents)
    }

    public func save(_ config: DeskConfig) throws {
        guard loaded else { throw SettingsFileError.notLoaded }
        try access(resolve()) { url in
            // Check readability again, without clearing a previous failure or recreating a missing file.
            _ = try String(contentsOf: url, encoding: .utf8)
            // Preserve symlinks used by dotfile managers.
            try config.document.text.write(to: url, atomically: false, encoding: .utf8)
        }
    }

    /// The file panel grants access before this call. Commit the choice only after it can be read and bookmarked.
    @discardableResult
    public func choose(_ url: URL) throws -> DeskConfig {
        let target = url.resolvingSymlinksInPath()
        return try access(target) { file in
            let config = DeskConfig(text: try String(contentsOf: file, encoding: .utf8))
            let bookmark = try file.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            self.file = file
            loaded = true
            loadWarning = nil
            return config
        }
    }

    private func resolve() throws -> URL {
        guard hasSelection else { return defaultFile }
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { throw SettingsFileError.bookmark }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            try access(url) { file in
                let renewed = try file.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(renewed, forKey: Self.bookmarkKey)
            }
        }
        return url
    }

    private func access<T>(_ url: URL, _ operation: (URL) throws -> T) rethrows -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try operation(url)
    }
}

private enum SettingsFileError: LocalizedError {
    case notLoaded, bookmark
    var errorDescription: String? {
        switch self {
        case .notLoaded: return "Settings have not loaded. Choose a readable settings file before saving."
        case .bookmark: return "The saved settings permission is invalid. Choose the settings file again."
        }
    }
}
