import Foundation

/// The four things a person can change to fix their posture.
public enum Adjustment: String, CaseIterable, Sendable {
    case screenHeight = "screen_height"
    case screenDistance = "screen_distance"
    case deskHeight = "desk_height"
    case chairHeight = "chair_height"

    public var label: String {
        switch self {
        case .screenHeight: return "Screen height"
        case .screenDistance: return "Screen distance"
        case .deskHeight: return "Desk height"
        case .chairHeight: return "Chair height"
        }
    }
}

/// Which camera a setup uses: the best one connected, the MacBook's own, or one by name.
public enum CameraChoice: Hashable, Sendable {
    case auto, builtIn, named(String)

    public init(_ text: String) {
        switch text {
        case "", "auto": self = .auto
        case "built-in": self = .builtIn
        default: self = .named(text)
        }
    }

    public var text: String {
        switch self {
        case .auto: return "auto"
        case .builtIn: return "built-in"
        case .named(let n): return n
        }
    }
}

/// One place Desk Undo is used: its camera, its screen, its tape measurements and what can be moved there.
public struct SetupProfile: Equatable, Sendable {
    public var name: String
    public var camera: CameraChoice
    public var screen: String
    public var measurements: Setup
    public var fixed: Set<Adjustment>

    public init(name: String, camera: CameraChoice = .auto, screen: String = "", measurements: Setup = Setup(),
                fixed: Set<Adjustment> = []) {
        self.name = name; self.camera = camera; self.screen = screen
        self.measurements = measurements; self.fixed = fixed
        self.measurements.builtIn = camera == .builtIn
    }

    /// A seated-only setup has no desk-height adjustment, so it has no standing preset.
    public var supportsStandingPreset: Bool { !fixed.contains(.deskHeight) }

    /// The external camera on an external screen, with an adjustable standing desk.
    public static func external(name: String) -> SetupProfile {
        SetupProfile(name: name, camera: .auto, screen: "external")
    }

    /// The MacBook's own camera and screen on a normal desk: seated only, so desk and screen height are fixed.
    public static func laptop(name: String) -> SetupProfile {
        SetupProfile(name: name, camera: .builtIn, screen: "MacBook",
                     fixed: [.deskHeight, .screenHeight])
    }
}
