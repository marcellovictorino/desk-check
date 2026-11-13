import Foundation

public enum Posture: String, CaseIterable, Sendable {
    case sit, stand
    public var label: String { self == .sit ? "Sit" : "Stand" }
}

/// A desk height read from the tape on the desk leg, plus what the camera saw at that height.
/// The camera numbers let a later check confirm the desk really is back where it was.
public struct DeskPreset: Equatable, Sendable {
    public var deskHeightCm: Double
    public var distanceCm: Double?
    public var eyeAboveScreenTopCm: Double?

    public init(deskHeightCm: Double, distanceCm: Double? = nil, eyeAboveScreenTopCm: Double? = nil) {
        self.deskHeightCm = deskHeightCm
        self.distanceCm = distanceCm
        self.eyeAboveScreenTopCm = eyeAboveScreenTopCm
    }

    /// How far a reading may differ from the remembered view and still count as the same place.
    public static let toleranceCm = 3.0

    public enum Confirmation: Equatable, Sendable {
        case confirmed
        case differs(String)
        /// The preset has no camera numbers yet.
        case notRemembered
    }

    public func confirm(_ r: PostureReading) -> Confirmation {
        guard let d = distanceCm, let h = eyeAboveScreenTopCm else { return .notRemembered }
        var problems: [String] = []
        let dd = r.distanceCm - d
        if abs(dd) > Self.toleranceCm {
            problems.append("the screen is \(Int(abs(dd).rounded())) cm \(dd > 0 ? "further" : "closer") than when you saved it")
        }
        let dh = r.eyeAboveScreenTopCm - h
        if abs(dh) > Self.toleranceCm {
            problems.append(
                "your eyes are \(Int(abs(dh).rounded())) cm \(dh > 0 ? "higher" : "lower") against the screen than when you saved it")
        }
        guard !problems.isEmpty else { return .confirmed }
        let sentence = problems.joined(separator: " and ")
        return .differs(sentence.prefix(1).uppercased() + sentence.dropFirst() + ". Check the tape reading.")
    }
}
