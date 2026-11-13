import Foundation

/// Per-webcam calibration, stored under `[webcams."<camera name>"]`.
public struct WebcamCalibration: Equatable, Sendable {
    public var focalWidths: Double?
    public var pitchDegrees: Double?
    public init(focalWidths: Double? = nil, pitchDegrees: Double? = nil) {
        self.focalWidths = focalWidths
        self.pitchDegrees = pitchDegrees
    }
}

/// Desk Check's settings, read from and written to `config.toml` without disturbing the person's comments.
///
/// A setup is a named place Desk Check is used, such as a standing desk with an external camera or a
/// MacBook on a normal desk. Setups live in `[setups."Name"]` tables; calibration stays per webcam.
public struct DeskConfig: Equatable {
    public var document: TOMLDocument

    public init(text: String) { document = TOMLDocument(text: text) }

    private static let preferences = "preferences"
    private static let fixedWord = "fixed"
    private static let adjustableWord = "adjustable"
    public static let defaultSetupName = "Standing desk"

    // MARK: Setups

    public var setupNames: [String] {
        let names = document.tableNames(prefix: "setups")
        return names.isEmpty ? [Self.defaultSetupName] : names
    }

    /// The setup last used, or the first one when it is unset or no longer exists.
    public var activeSetupName: String {
        get {
            if case .string(let n)? = document.value("active_setup", in: Self.preferences), setupNames.contains(n) { return n }
            return setupNames[0]
        }
        set { document.set("active_setup", .string(newValue), in: Self.preferences) }
    }

    public var autoSwitch: Bool {
        get { if case .bool(let b)? = document.value("auto_switch", in: Self.preferences) { return b } else { return false } }
        set { document.set("auto_switch", .bool(newValue), in: Self.preferences) }
    }

    public func profile(named name: String) -> SetupProfile {
        let table = TOMLDocument.tableName(setup: name)
        guard document.hasTable(table) else { return .external(name: name) }
        func n(_ key: String) -> Double? {
            if case .number(let v)? = document.value(key, in: table), v > 0 { return v }
            return nil
        }
        func str(_ key: String) -> String {
            if case .string(let v)? = document.value(key, in: table) { return v }
            return ""
        }
        var fixed = Set<Adjustment>()
        for a in Adjustment.allCases {
            if case .string(Self.fixedWord)? = document.value(a.rawValue, in: table) { fixed.insert(a) }
        }
        let measurements = Setup(
            screenDistanceCm: n("screen_distance_cm"), screenTopHeightCm: n("screen_top_height_cm"),
            lensOffsetCm: n("lens_offset_cm"), userHeightCm: n("user_height_cm"),
            seatedEyeHeightCm: n("seated_eye_height_cm"), eyeToElbowCm: n("eye_to_elbow_cm"))
        var presets: [Posture: DeskPreset] = [:]
        for posture in Posture.allCases {
            let key = posture.rawValue
            guard let desk = n("\(key)_desk_height_cm") else { continue }
            presets[posture] = DeskPreset(
                deskHeightCm: desk, distanceCm: n("\(key)_distance_cm"),
                eyeAboveScreenTopCm: number("\(key)_eye_above_screen_top_cm", in: table))
        }
        return SetupProfile(
            name: name, camera: CameraChoice(str("camera")), screen: str("screen"),
            measurements: measurements, fixed: fixed, presets: presets)
    }

    /// A number that may be zero or negative, such as eyes below the top of the screen.
    private func number(_ key: String, in table: String) -> Double? {
        if case .number(let v)? = document.value(key, in: table) { return v }
        return nil
    }

    public var activeProfile: SetupProfile { profile(named: activeSetupName) }

    /// Writes every field of the setup. Measurements left empty are removed so the default applies.
    public mutating func save(_ p: SetupProfile) {
        let table = TOMLDocument.tableName(setup: p.name)
        let m = p.measurements
        document.set("camera", .string(p.camera.text), in: table)
        document.set("screen", .string(p.screen), in: table)
        for (key, v) in [
            ("screen_distance_cm", m.screenDistanceCm), ("screen_top_height_cm", m.screenTopHeightCm),
            ("lens_offset_cm", m.lensOffsetCm), ("user_height_cm", m.userHeightCm),
            ("seated_eye_height_cm", m.seatedEyeHeightCm), ("eye_to_elbow_cm", m.eyeToElbowCm),
        ] {
            if let v { document.set(key, .number(v), in: table) } else { document.remove(key, in: table) }
        }
        for posture in Posture.allCases {
            let key = posture.rawValue
            // A setup with a fixed desk has no standing preset.
            let preset = (posture == .stand && !p.supportsStandingPreset) ? nil : p.presets[posture]
            for (suffix, v) in [
                ("desk_height_cm", preset?.deskHeightCm), ("distance_cm", preset?.distanceCm),
                ("eye_above_screen_top_cm", preset?.eyeAboveScreenTopCm),
            ] {
                if let v { document.set("\(key)_\(suffix)", .number(v), in: table) } else { document.remove("\(key)_\(suffix)", in: table) }
            }
        }
        for a in Adjustment.allCases {
            document.set(a.rawValue, .string(p.fixed.contains(a) ? Self.fixedWord : Self.adjustableWord), in: table)
        }
    }

    /// Adds a setup from a template. Returns false when the name is empty or taken.
    @discardableResult
    public mutating func addSetup(_ template: SetupProfile) -> Bool {
        guard isFreeName(template.name) else { return false }
        materialiseDefaultSetup()
        save(template)
        return true
    }

    @discardableResult
    public mutating func renameSetup(_ old: String, to new: String) -> Bool {
        guard isFreeName(new), setupNames.contains(old) else { return false }
        materialiseDefaultSetup()
        let wasActive = activeSetupName == old
        document.renameTable(TOMLDocument.tableName(setup: old), to: TOMLDocument.tableName(setup: new))
        if wasActive { activeSetupName = new }
        return true
    }

    @discardableResult
    public mutating func duplicateSetup(_ old: String, as new: String) -> Bool {
        guard isFreeName(new), setupNames.contains(old) else { return false }
        materialiseDefaultSetup()
        document.duplicateTable(TOMLDocument.tableName(setup: old), as: TOMLDocument.tableName(setup: new))
        return true
    }

    /// Deletes a setup. The last one cannot be deleted.
    @discardableResult
    public mutating func deleteSetup(_ name: String) -> Bool {
        materialiseDefaultSetup()
        guard setupNames.count > 1, setupNames.contains(name) else { return false }
        let wasActive = activeSetupName == name
        document.removeTable(TOMLDocument.tableName(setup: name))
        if wasActive { activeSetupName = setupNames[0] }
        return true
    }

    private func isFreeName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed == name && !document.tableNames(prefix: "setups").contains(name)
    }

    /// A file with no setup tables shows the default setup; writing the first change makes it real.
    private mutating func materialiseDefaultSetup() {
        if document.tableNames(prefix: "setups").isEmpty { save(.external(name: Self.defaultSetupName)) }
    }

    /// The setup to switch to when webcams are plugged in or unplugged, or nil to leave things alone.
    /// With an external webcam connected, only setups that can use it qualify; otherwise any setup the
    /// connected cameras can serve does. The setup already in use wins when it qualifies.
    public func suggestedSetup(externalCameras: [String], builtInCameras: [String]) -> String? {
        let qualifying = setupNames.filter { name in
            switch profile(named: name).camera {
            case .auto: return !externalCameras.isEmpty || !builtInCameras.isEmpty
            case .builtIn: return externalCameras.isEmpty && !builtInCameras.isEmpty
            case .named(let n): return externalCameras.contains(n) || (externalCameras.isEmpty && builtInCameras.contains(n))
            }
        }
        return qualifying.contains(activeSetupName) ? activeSetupName : qualifying.first
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
        # Desk Check settings. Lines starting with # are comments; the app keeps them when it saves.
        # Delete a measurement line to go back to the default estimate. Lengths are in centimetres.

        [preferences]
        # The setup used last; the menu bar popover and Settings change it.
        active_setup = "Standing desk"
        # Switch setup by itself when a webcam is plugged in or unplugged.
        auto_switch = false
        # Show the camera view with detected eye points during a check. The picture is never saved.
        preview = false

        # A setup is one place you use Desk Check. Copy a table and rename it to add another, for example
        # [setups."MacBook on the sofa table"] with camera = "built-in".
        [setups."Standing desk"]
        # "auto" is an external webcam when one is plugged in, else the MacBook's. "built-in" is always
        # the MacBook's own. Or write a webcam name exactly as macOS shows it.
        camera = "auto"
        screen = "external"
        # Tape measure, eye to screen surface, while you sit as you normally do. Used to calibrate the webcam.
        # screen_distance_cm = 60
        # Top edge of the screen above the desk surface (default 45; 24 for the built-in screen).
        # screen_top_height_cm = 45
        # Webcam lens centre above the top edge of the screen (default 1; 0.5 for the built-in camera).
        # lens_offset_cm = 1
        # Your height, and your eyes above the desk surface when seated.
        # user_height_cm = 175
        # seated_eye_height_cm = 40
        # Vertical gap from your eyes to your elbow (default 0.3 of your height). Live mode keeps the
        # desk surface 3 cm below your elbow.
        # eye_to_elbow_cm = 52
        # Desk presets: the height read from the tape on the desk leg. The camera numbers are added
        # by the popover's "Remember view" and let it confirm you are back at the same height.
        # sit_desk_height_cm = 72
        # stand_desk_height_cm = 112
        # What you can move here: "adjustable" or "fixed". A setup with a fixed desk has no standing preset.
        screen_height = "adjustable"
        screen_distance = "adjustable"
        desk_height = "adjustable"
        chair_height = "adjustable"

        # Webcam calibration is stored per webcam, not per setup, and is added here by Settings:
        # [webcams."HD Pro Webcam C920"]
        # focal_widths = 0.78
        # pitch_degrees = 0

        """
}
