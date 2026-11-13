import Foundation

public struct Advice: Equatable, Sendable {
    public enum Status: Sendable { case good, adjust, fixed }
    public var status: Status
    public var sentence: String
}

/// One sentence per adjustment, each with a number.
public enum AdviceEngine {
    /// Comfortable eye-to-screen distance in cm, and the distance advice aims for when outside it.
    public static let distanceBand = 50.0...70.0
    public static let distanceTarget = 60.0
    /// Comfortable height of the eyes above the top edge of the screen in cm, and the aim when outside it.
    public static let heightBand = 0.0...10.0
    public static let heightTarget = 5.0

    /// A fixed adjustment cannot be moved in the current setup, so it is reported but not advised.
    public static func advise(_ r: PostureReading, fixed: Set<Adjustment> = []) -> [Advice] {
        let distance =
            fixed.contains(.screenDistance)
            ? Advice(status: .fixed, sentence: "Screen distance is fixed in this setup; it is \(cm(r.distanceCm)) from your eyes.")
            : screenDistance(r.distanceCm)
        let height =
            fixed.contains(.screenHeight)
            ? Advice(status: .fixed, sentence: "Screen height is fixed in this setup; your eyes are \(relative(r.eyeAboveScreenTopCm)).")
            : screenHeight(r.eyeAboveScreenTopCm)
        return [distance, height]
    }

    static func screenDistance(_ d: Double) -> Advice {
        if distanceBand.contains(d) {
            return Advice(status: .good, sentence: "Distance: right at \(cm(d)).")
        }
        let move = abs(distanceTarget - d)
        let direction = d < distanceBand.lowerBound ? "further away" : "closer"
        return Advice(status: .adjust, sentence: "Distance: move the screen \(cm(move)) \(direction).")
    }

    static func screenHeight(_ eyeAboveTop: Double) -> Advice {
        let position = relative(eyeAboveTop)
        if heightBand.contains(eyeAboveTop) {
            return Advice(status: .good, sentence: "Screen: height is right, eyes \(position).")
        }
        let move = abs(heightTarget - eyeAboveTop)
        let verb = eyeAboveTop < heightBand.lowerBound ? "Lower" : "Raise"
        return Advice(status: .adjust, sentence: "Screen: \(verb.lowercased()) \(cm(move)).")
    }

    private static func cm(_ v: Double) -> String { "\(Int(v.rounded())) cm" }

    private static func relative(_ v: Double) -> String {
        let r = Int(v.rounded())
        return r >= 0 ? "\(r) cm above its top edge" : "\(-r) cm below its top edge"
    }
}
