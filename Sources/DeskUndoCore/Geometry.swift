import Foundation

/// The two eye positions in one camera frame, in pixels with the origin at the bottom left.
public struct EyePoints: Equatable, Sendable {
    public var left: Point
    public var right: Point
    public var imageWidth: Double
    public var imageHeight: Double
    /// Head turn left or right in radians, when the face detector reports it.
    public var yaw: Double

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public init(left: Point, right: Point, imageWidth: Double, imageHeight: Double, yaw: Double = 0) {
        self.left = left; self.right = right
        self.imageWidth = imageWidth; self.imageHeight = imageHeight; self.yaw = yaw
    }

    /// Pixel distance between the eyes, corrected for a turned head.
    var spanPixels: Double {
        let apparent = hypot(right.x - left.x, right.y - left.y)
        return apparent / max(cos(min(abs(yaw), 1.0)), 0.5)
    }

    var midpointY: Double { (left.y + right.y) / 2 }
}

/// What the lens does to a person's position: field of view, per webcam, and how far it tilts.
public struct CameraModel: Equatable, Sendable {
    /// Focal length as a multiple of the image width: 0.5 / tan(horizontal field of view / 2).
    public var focalWidths: Double
    /// Upward tilt of the lens in radians; 0 when the webcam looks straight at the person.
    public var pitch: Double

    public init(focalWidths: Double, pitch: Double = 0) {
        self.focalWidths = focalWidths; self.pitch = pitch
    }

    public init(fieldOfViewDegrees: Double) {
        self.init(focalWidths: 0.5 / tan(fieldOfViewDegrees * .pi / 360))
    }
}

/// Tape-measure inputs. `nil` means not measured, so the default estimate applies.
public struct Setup: Equatable, Sendable {
    public var screenDistanceCm: Double?
    public var screenTopHeightCm: Double?
    public var lensOffsetCm: Double?
    public var userHeightCm: Double?
    public var seatedEyeHeightCm: Double?

    /// True for the MacBook's own camera and screen, which sit lower and nearer the desk than an external screen.
    public var builtIn: Bool

    public static let defaultUserHeightCm = 175.0
    public var defaultScreenTopHeightCm: Double { builtIn ? 24 : 45 }
    public var defaultLensOffsetCm: Double { builtIn ? 0.5 : 1 }

    public init(screenDistanceCm: Double? = nil, screenTopHeightCm: Double? = nil, lensOffsetCm: Double? = nil,
                userHeightCm: Double? = nil, seatedEyeHeightCm: Double? = nil, builtIn: Bool = false) {
        self.builtIn = builtIn
        self.screenDistanceCm = screenDistanceCm; self.screenTopHeightCm = screenTopHeightCm
        self.lensOffsetCm = lensOffsetCm; self.userHeightCm = userHeightCm; self.seatedEyeHeightCm = seatedEyeHeightCm
    }

    public var screenTop: Double { screenTopHeightCm ?? defaultScreenTopHeightCm }
    public var lensOffset: Double { lensOffsetCm ?? defaultLensOffsetCm }
    public var userHeight: Double { userHeightCm ?? Self.defaultUserHeightCm }
    /// Eye height above the desk when seated, estimated from body height when not measured.
    public var seatedEyeHeight: Double { seatedEyeHeightCm ?? userHeight * 0.23 }
}

public struct PostureReading: Equatable, Sendable {
    /// Eye to screen, along the camera's axis.
    public var distanceCm: Double
    /// Positive when the eyes are above the top edge of the screen.
    public var eyeAboveScreenTopCm: Double
    public var eyeHeightAboveDeskCm: Double
}

public enum Geometry {
    /// Typical distance between the pupils of an adult. Calibration absorbs a person's difference from it.
    public static let defaultEyeSpanCm = 6.3

    /// Pinhole model: the eyes' real span over their span in the frame is the distance over the focal length.
    public static func reading(_ eyes: EyePoints, camera: CameraModel, setup: Setup,
                               eyeSpanCm: Double = defaultEyeSpanCm) -> PostureReading? {
        let span = eyes.spanPixels
        guard span > 1, eyes.imageWidth > 0 else { return nil }
        let focalPx = camera.focalWidths * eyes.imageWidth
        let distance = focalPx * eyeSpanCm / span
        let angle = atan((eyes.midpointY - eyes.imageHeight / 2) / focalPx) + camera.pitch
        let aboveLens = distance * tan(angle)
        let aboveTop = setup.lensOffset + aboveLens
        return PostureReading(distanceCm: distance, eyeAboveScreenTopCm: aboveTop,
                              eyeHeightAboveDeskCm: setup.screenTop + aboveTop)
    }

    /// Focal length that makes this frame read `tapeDistanceCm`, the eye-to-screen distance measured with a tape.
    public static func calibrateFocal(_ eyes: EyePoints, tapeDistanceCm: Double,
                                      eyeSpanCm: Double = defaultEyeSpanCm) -> Double? {
        let span = eyes.spanPixels
        guard span > 1, eyes.imageWidth > 0, tapeDistanceCm > 0 else { return nil }
        return tapeDistanceCm * span / (eyeSpanCm * eyes.imageWidth)
    }

    /// Lens tilt that makes this frame put the eyes at the tape-measured seated eye height.
    /// Needs the seated eye height and the distance to be tape measures, not defaults.
    public static func calibratePitch(_ eyes: EyePoints, focalWidths: Double, tapeDistanceCm: Double,
                                      lensHeightAboveDeskCm: Double, eyeHeightAboveDeskCm: Double) -> Double? {
        guard tapeDistanceCm > 0, eyes.imageWidth > 0 else { return nil }
        let expected = atan((eyeHeightAboveDeskCm - lensHeightAboveDeskCm) / tapeDistanceCm)
        let measured = atan((eyes.midpointY - eyes.imageHeight / 2) / (focalWidths * eyes.imageWidth))
        let pitch = expected - measured
        return abs(pitch) < 30 * .pi / 180 ? pitch : nil
    }

    /// The middle reading of many frames, so one bad frame cannot move the result.
    public static func median(_ readings: [PostureReading]) -> PostureReading? {
        guard !readings.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double {
            let s = values.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        return PostureReading(distanceCm: mid(readings.map(\.distanceCm)),
                              eyeAboveScreenTopCm: mid(readings.map(\.eyeAboveScreenTopCm)),
                              eyeHeightAboveDeskCm: mid(readings.map(\.eyeHeightAboveDeskCm)))
    }
}
