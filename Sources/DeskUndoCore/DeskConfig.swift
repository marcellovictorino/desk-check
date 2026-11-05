import Foundation

/// Per-webcam calibration, stored under `[webcams."<camera name>"]`.
public struct WebcamCalibration: Equatable, Sendable {
    public var focalWidths: Double?
    public var pitchDegrees: Double?
    public init(focalWidths: Double? = nil, pitchDegrees: Double? = nil) {
        self.focalWidths = focalWidths; self.pitchDegrees = pitchDegrees
    }
}

/// Desk Undo's settings, read from and written to `config.toml` without disturbing the person's comments.
public struct DeskConfig: Equatable {
    public var document: TOMLDocument

    public init(text: String) { document = TOMLDocument(text: text) }

    private static let measurements = "measurements"
    private static let preferences = "preferences"

    public var setup: Setup {
        get {
            func n(_ key: String) -> Double? {
                if case .number(let v)? = document.value(key, in: Self.measurements), v > 0 { return v }
                return nil
            }
            return Setup(screenDistanceCm: n("screen_distance_cm"), screenTopHeightCm: n("screen_top_height_cm"),
                         lensOffsetCm: n("lens_offset_cm"), userHeightCm: n("user_height_cm"),
                         seatedEyeHeightCm: n("seated_eye_height_cm"))
        }
        set {
            func put(_ key: String, _ v: Double?) {
                if let v { document.set(key, .number(v), in: Self.measurements) }
                else { document.remove(key, in: Self.measurements) }
            }
            put("screen_distance_cm", newValue.screenDistanceCm)
            put("screen_top_height_cm", newValue.screenTopHeightCm)
            put("lens_offset_cm", newValue.lensOffsetCm)
            put("user_height_cm", newValue.userHeightCm)
            put("seated_eye_height_cm", newValue.seatedEyeHeightCm)
        }
    }

    public var showPreview: Bool {
        get { if case .bool(let b)? = document.value("preview", in: Self.preferences) { return b } else { return false } }
        set { document.set("preview", .bool(newValue), in: Self.preferences) }
    }

    public func calibration(forWebcam name: String) -> WebcamCalibration {
        let table = TOMLDocument.tableName(webcam: name)
        var c = WebcamCalibration()
        if case .number(let v)? = document.value("focal_widths", in: table), v > 0 { c.focalWidths = v }
        if case .number(let v)? = document.value("pitch_degrees", in: table) { c.pitchDegrees = v }
        return c
    }

    public mutating func setCalibration(_ c: WebcamCalibration, forWebcam name: String) {
        let table = TOMLDocument.tableName(webcam: name)
        if let f = c.focalWidths { document.set("focal_widths", .number(f), in: table) }
        if let p = c.pitchDegrees { document.set("pitch_degrees", .number(p), in: table) }
    }

    public mutating func clearCalibration(forWebcam name: String) {
        let table = TOMLDocument.tableName(webcam: name)
        document.remove("focal_widths", in: table)
        document.remove("pitch_degrees", in: table)
    }

    /// macOS does not report a webcam's field of view, so uncalibrated webcams assume a typical 70 degrees.
    public static let typicalFieldOfViewDegrees = 70.0

    /// The camera model for a webcam: its calibration where measured, else its reported field of view.
    public func camera(forWebcam name: String, fieldOfViewDegrees: Double?) -> CameraModel {
        let c = calibration(forWebcam: name)
        let fallback = CameraModel(fieldOfViewDegrees: fieldOfViewDegrees ?? Self.typicalFieldOfViewDegrees).focalWidths
        return CameraModel(focalWidths: c.focalWidths ?? fallback, pitch: (c.pitchDegrees ?? 0) * .pi / 180)
    }

    public static let starterContents = """
    # Desk Undo settings. Lines starting with # are comments; the app keeps them when it saves.
    # Delete a line to go back to the default estimate. Lengths are in centimetres.

    [measurements]
    # Tape measure, eye to screen surface, while you sit as you normally do.
    # Used to calibrate the webcam; leave out until you have measured it.
    # screen_distance_cm = 60
    # Top edge of the screen above the desk surface (default 45).
    # screen_top_height_cm = 45
    # Webcam lens centre above the top edge of the screen (default 1).
    # lens_offset_cm = 1
    # Your height, and your eyes above the desk surface when seated.
    # user_height_cm = 175
    # seated_eye_height_cm = 40

    [preferences]
    # Show the camera view with detected eye points during a check. The picture is never saved.
    preview = false

    # Webcam calibration is added here by Settings, one table per webcam name, for example:
    # [webcams."HD Pro Webcam C920"]
    # focal_widths = 0.78
    # pitch_degrees = 0

    """
}
