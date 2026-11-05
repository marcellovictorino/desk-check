import Foundation

public struct Advice: Equatable, Sendable {
    public enum Status: Sendable { case good, adjust }
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

    public static func advise(_ r: PostureReading) -> [Advice] {
        [screenDistance(r.distanceCm), screenHeight(r.eyeAboveScreenTopCm)]
    }

    static func screenDistance(_ d: Double) -> Advice {
        if distanceBand.contains(d) {
            return Advice(status: .good, sentence: "Screen distance is right at \(cm(d)).")
        }
        let move = abs(distanceTarget - d)
        let direction = d < distanceBand.lowerBound ? "further away" : "closer"
        return Advice(status: .adjust, sentence: "Move the screen \(cm(move)) \(direction); it is \(cm(d)) from your eyes.")
    }

    static func screenHeight(_ eyeAboveTop: Double) -> Advice {
        let position = relative(eyeAboveTop)
        if heightBand.contains(eyeAboveTop) {
            return Advice(status: .good, sentence: "Screen height is right: your eyes are \(position).")
        }
        let move = abs(heightTarget - eyeAboveTop)
        let verb = eyeAboveTop < heightBand.lowerBound ? "Lower" : "Raise"
        return Advice(status: .adjust, sentence: "\(verb) the screen by \(cm(move)); your eyes are \(position).")
    }

    private static func cm(_ v: Double) -> String { "\(Int(v.rounded())) cm" }

    private static func relative(_ v: Double) -> String {
        let r = Int(v.rounded())
        return r >= 0 ? "\(r) cm above its top edge" : "\(-r) cm below its top edge"
    }
}
