import Foundation

/// Whether a live session is running, and which one. Stop only ever stops, and a camera or reading
/// that belongs to an earlier session is told apart from the current one by its token.
public struct LiveRun: Equatable, Sendable {
    public private(set) var isRunning = false
    private var current = 0

    public init() {}

    /// Begins a session and returns its token, or nil when one is already running.
    public mutating func start() -> Int? {
        guard !isRunning else { return nil }
        isRunning = true
        current += 1
        return current
    }

    /// Ends the session. False when none was running, so a late or repeated Stop does nothing.
    @discardableResult
    public mutating func stop() -> Bool {
        guard isRunning else { return false }
        isRunning = false
        return true
    }

    /// True while `token` is the running session, false once it was stopped or replaced.
    public func isCurrent(_ token: Int) -> Bool { isRunning && token == current }
}

/// Sizes that keep the live view the same height whatever the camera sees, so Stop never moves.
public enum LiveLayout {
    public static let rowHeight = 44.0
    public static let rowSpacing = 8.0
    /// The most adjustments live mode shows: screen distance, screen height and desk height.
    public static let maximumRows = 3

    /// Height reserved for the band rows of a setup with `rows` adjustable adjustments.
    public static func bandAreaHeight(rows: Int) -> Double {
        let n = Double(min(max(rows, 1), maximumRows))
        return n * rowHeight + (n - 1) * rowSpacing
    }
}
