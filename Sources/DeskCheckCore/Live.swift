import Foundation

public enum BandLevel: Int, Comparable, Sendable {
    case green, yellow, red
    public static func < (a: BandLevel, b: BandLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Which way to move a thing to bring it back to its target.
public enum MoveDirection: Sendable {
    case up, down, closer, further, none
}

/// A target with a green zone and a wider yellow zone around it; beyond that is red.
public struct Band: Equatable, Sendable {
    public var target: Double
    public var green: Double
    public var yellow: Double

    public func level(of value: Double) -> BandLevel {
        let off = abs(value - target)
        return off <= green ? .green : off <= yellow ? .yellow : .red
    }

    /// Top of the screen 2 cm below eye level, so the eyes sit 2 cm above its top edge.
    public static let screenTop = Band(target: 2, green: 3, yellow: 6)
    /// Eye to screen distance.
    public static let distance = Band(target: 62, green: 12, yellow: 20)
    /// Desk surface 3 cm below the elbow.
    public static let deskBelowElbowCm = 3.0
    public static let desk = Band(target: deskBelowElbowCm, green: 3, yellow: 6)
}

/// What live mode shows for one adjustment: colour, an arrow and a number.
public struct LiveAdvice: Equatable, Sendable {
    public var adjustment: Adjustment
    public var level: BandLevel
    public var direction: MoveDirection
    /// Centimetres to move; what the arrow's number shows.
    public var moveCm: Int
    public var text: String
}

public enum LiveEngine {
    /// Screen height, screen distance and desk height. Fixed adjustments are left out: they cannot be moved here.
    public static func advise(_ r: PostureReading, setup: Setup, fixed: Set<Adjustment>) -> [LiveAdvice] {
        var out: [LiveAdvice] = []
        if !fixed.contains(.screenDistance) {
            // Positive when the screen is further than the target.
            let off = r.distanceCm - Band.distance.target
            out.append(
                make(
                    .screenDistance, Band.distance.level(of: r.distanceCm), off > 0 ? .closer : .further, off,
                    noun: "screen", closer: "Bring the screen closer", further: "Move the screen further away"))
        }
        if !fixed.contains(.screenHeight) {
            // Eyes higher above the screen top than the target means the screen is too low.
            let off = r.eyeAboveScreenTopCm - Band.screenTop.target
            out.append(
                make(
                    .screenHeight, Band.screenTop.level(of: r.eyeAboveScreenTopCm), off > 0 ? .up : .down, off,
                    noun: "screen", up: "Raise the screen", down: "Lower the screen"))
        }
        if !fixed.contains(.deskHeight) {
            // The desk should sit 3 cm below the elbow, so the eyes sit one eye-to-elbow gap plus 3 cm above it.
            let target = setup.eyeToElbow + Band.deskBelowElbowCm
            let off = r.eyeHeightAboveDeskCm - target
            let level = Band(target: 0, green: Band.desk.green, yellow: Band.desk.yellow).level(of: off)
            out.append(make(.deskHeight, level, off > 0 ? .up : .down, off, noun: "desk", up: "Raise the desk", down: "Lower the desk"))
        }
        return out
    }

    private static func make(
        _ a: Adjustment, _ level: BandLevel, _ dir: MoveDirection, _ off: Double, noun: String,
        closer: String = "", further: String = "", up: String = "", down: String = ""
    ) -> LiveAdvice {
        let cm = Int(abs(off).rounded())
        if level == .green {
            return LiveAdvice(adjustment: a, level: .green, direction: .none, moveCm: cm, text: "\(a.label) is right.")
        }
        let verb: String
        switch dir {
        case .closer: verb = closer
        case .further: verb = further
        case .up: verb = up
        default: verb = down
        }
        return LiveAdvice(adjustment: a, level: level, direction: dir, moveCm: cm, text: "\(verb) by \(cm) cm.")
    }
}

/// Averages the readings of the last moment, so the number does not jump with every frame.
public struct RollingAverage: Sendable {
    public var window: TimeInterval
    /// Fewest readings worth showing; a single frame is too noisy.
    public var minimumCount: Int
    private var entries: [(time: TimeInterval, reading: PostureReading)] = []

    public init(window: TimeInterval = 1.0, minimumCount: Int = 3) {
        self.window = window
        self.minimumCount = minimumCount
    }

    public mutating func add(_ r: PostureReading, at time: TimeInterval) {
        entries.append((time, r))
        entries.removeAll { time - $0.time > window }
    }

    public mutating func reset() { entries.removeAll() }

    public var average: PostureReading? {
        guard entries.count >= minimumCount else { return nil }
        let n = Double(entries.count)
        return PostureReading(
            distanceCm: entries.reduce(0) { $0 + $1.reading.distanceCm } / n,
            eyeAboveScreenTopCm: entries.reduce(0) { $0 + $1.reading.eyeAboveScreenTopCm } / n,
            eyeHeightAboveDeskCm: entries.reduce(0) { $0 + $1.reading.eyeHeightAboveDeskCm } / n)
    }
}
