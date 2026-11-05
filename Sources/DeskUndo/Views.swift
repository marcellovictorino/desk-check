import DeskUndoCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var checker: PostureChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Desk Undo").font(.headline)
                Spacer()
                if checker.setupNames.count > 1 {
                    Picker("Setup", selection: Binding(get: { checker.activeSetup }, set: { checker.selectSetup($0) })) {
                        ForEach(checker.setupNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize().disabled(checker.isRunning)
                } else {
                    Text(checker.activeSetup).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let preview = checker.preview { PreviewView(frame: preview) }
            if let r = checker.reading {
                ForEach(Array(checker.advice.enumerated()), id: \.offset) { _, item in
                    Label(item.sentence, systemImage: item.status == .good ? "checkmark.circle.fill" : item.status == .fixed ? "lock.circle.fill" : "arrow.up.and.down.circle.fill")
                        .foregroundStyle(item.status == .good ? Color.green : item.status == .fixed ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(String(format: "Eyes %.0f cm from the screen, %.0f cm above the desk.", r.distanceCm, r.eyeHeightAboveDeskCm))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = checker.calibrationNote {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(checker.statusText)
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Check posture") { checker.check() }
                    .disabled(checker.isRunning)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            Text("Camera permission: \(checker.permissionText)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { checker.reloadSetups(); checker.refreshPermission() }
        .onDisappear { checker.clearPreview() }
    }
}

/// The camera picture with the detected eye points, drawn mirrored like a mirror. Shown only while a check runs.
struct PreviewView: View {
    let frame: PreviewFrame

    var body: some View {
        Image(decorative: frame.image, scale: 1)
            .resizable().aspectRatio(contentMode: .fit)
            .overlay(GeometryReader { geo in
                ForEach([frame.left, frame.right], id: \.x) { p in
                    Circle().stroke(Color.green, lineWidth: 2).frame(width: 12, height: 12)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            })
            .scaleEffect(x: -1, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Camera preview with detected eye points")
    }
}

struct SettingsView: View {
    @ObservedObject var checker: PostureChecker
    @State private var profile = SetupProfile.external(name: "")
    @State private var fields = Fields()
    @State private var showPreview = false
    @State private var autoSwitch = false
    @State private var nameField = ""
    @State private var message = ""

    struct Fields {
        var distance = "", screenTop = "", lens = "", height = "", seatedEye = ""
    }

    var body: some View {
        Form {
            Section("Setup") {
                Picker("Setup", selection: Binding(get: { checker.activeSetup }, set: { switchSetup(to: $0) })) {
                    ForEach(checker.setupNames, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Name") {
                    TextField("", text: $nameField, prompt: Text("new or renamed setup")).frame(width: 200)
                }
                HStack {
                    Button("Rename") { edit { $0.renameSetup(checker.activeSetup, to: nameField) } }
                    Button("Duplicate") { edit { $0.duplicateSetup(checker.activeSetup, as: nameField) } }
                    Menu("Add") {
                        Button("External camera and screen") { edit { $0.addSetup(.external(name: nameField)) } }
                        Button("MacBook camera and screen") { edit { $0.addSetup(.laptop(name: nameField)) } }
                    }.fixedSize()
                    Button("Delete", role: .destructive) { edit { $0.deleteSetup(checker.activeSetup) } }
                        .disabled(checker.setupNames.count < 2)
                }
                Text("Rename, Duplicate and Add use the name above. Delete removes the selected setup; its webcam calibration stays.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Switch setup when a webcam is plugged in or unplugged", isOn: $autoSwitch)
            }
            Section("Camera and screen") {
                Picker("Camera", selection: $profile.camera) {
                    Text("Automatic (external if plugged in)").tag(CameraChoice.auto)
                    Text("MacBook built-in camera").tag(CameraChoice.builtIn)
                    ForEach(namedCameras, id: \.self) { Text($0).tag(CameraChoice.named($0)) }
                }
                LabeledContent("Screen") {
                    TextField("", text: $profile.screen, prompt: Text("a label, e.g. Studio Display")).multilineTextAlignment(.trailing).frame(width: 200)
                }
                ForEach(Adjustment.allCases, id: \.self) { a in
                    Picker(a.label, selection: Binding(get: { profile.fixed.contains(a) },
                                                       set: { if $0 { profile.fixed.insert(a) } else { profile.fixed.remove(a) } })) {
                        Text("Adjustable").tag(false)
                        Text("Fixed").tag(true)
                    }.pickerStyle(.segmented)
                }
                if !profile.supportsStandingPreset {
                    Text("Desk height is fixed, so this setup has no standing preset.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Tape measure (centimetres)") {
                field("Eye to screen, seated", $fields.distance, hint: "for calibration")
                field("Top of screen above desk", $fields.screenTop, hint: "default \(fmt(defaults.screenTop))")
                field("Webcam lens above screen top", $fields.lens, hint: "default \(fmt(defaults.lensOffset))")
                field("Your height", $fields.height, hint: "default \(Int(Setup.defaultUserHeightCm))")
                field("Seated eyes above desk", $fields.seatedEye, hint: "estimated from height")
                Text("Leave a field empty to use the default estimate.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Webcam calibration") {
                Text(checker.webcamName ?? "The camera for this setup is not connected")
                Text("Sit as you normally do with your eyes at the tape distance, then calibrate. Calibration belongs to the webcam, so every setup using it shares it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Calibrate webcam") { save(); checker.calibrate() }
                        .disabled(checker.isRunning || checker.webcamName == nil)
                    if checker.isRunning { ProgressView().controlSize(.small) }
                }
                Text(checker.lastCalibrationText ?? calibrationSummary).font(.caption).foregroundStyle(.secondary)
                Toggle("Show camera preview with eye points during a check", isOn: $showPreview)
            }
            HStack {
                Button("Save") { save(); message = "Saved." }.keyboardShortcut(.defaultAction)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Config file", value: ConfigLocation.file.path).font(.caption)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear { checker.reloadSetups(); checker.refreshPermission(); load() }
    }

    private var defaults: Setup { Setup(builtIn: profile.camera == .builtIn) }
    private func fmt(_ v: Double) -> String { String(format: "%g", v) }

    private var namedCameras: [String] {
        var names = FaceSampler.connectedCameras().filter { $0.deviceType == .external }.map(\.localizedName)
        if case .named(let n) = profile.camera, !names.contains(n) { names.append(n) }
        return names
    }

    private var calibrationSummary: String {
        guard let name = checker.webcamName else { return "" }
        let c = ConfigLocation.load().calibration(forWebcam: name)
        guard let f = c.focalWidths else { return "Not calibrated: distances assume a typical 70 degree field of view." }
        return String(format: "Calibrated: focal length %.3f image widths, tilt %.1f°.", f, c.pitchDegrees ?? 0)
    }

    private func field(_ label: String, _ text: Binding<String>, hint: String) -> some View {
        LabeledContent(label) {
            TextField("", text: text, prompt: Text(hint)).multilineTextAlignment(.trailing).frame(width: 140)
        }
    }

    private func load() {
        let config = ConfigLocation.load()
        profile = config.activeProfile
        let s = profile.measurements
        func str(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "" }
        fields = Fields(distance: str(s.screenDistanceCm), screenTop: str(s.screenTopHeightCm), lens: str(s.lensOffsetCm),
                        height: str(s.userHeightCm), seatedEye: str(s.seatedEyeHeightCm))
        showPreview = config.showPreview
        autoSwitch = config.autoSwitch
        nameField = ""
    }

    /// Writes the form into the config file under the setup being edited.
    private func save() {
        func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        var config = ConfigLocation.load()
        var p = profile
        p.measurements = Setup(screenDistanceCm: num(fields.distance), screenTopHeightCm: num(fields.screenTop),
                               lensOffsetCm: num(fields.lens), userHeightCm: num(fields.height),
                               seatedEyeHeightCm: num(fields.seatedEye))
        config.save(p)
        config.showPreview = showPreview
        config.autoSwitch = autoSwitch
        write(config)
    }

    private func write(_ config: DeskConfig) {
        do { try ConfigLocation.save(config) } catch { message = "Could not save: \(error.localizedDescription)" }
    }

    private func switchSetup(to name: String) {
        save()
        checker.selectSetup(name)
        load()
    }

    /// Saves the form, applies one setup-list change, and reloads. The change says whether it applied.
    private func edit(_ change: (inout DeskConfig) -> Bool) {
        save()
        var config = ConfigLocation.load()
        let before = config.activeSetupName
        guard change(&config) else {
            message = "Not changed: the name must be new and not empty, and the last setup cannot be deleted."
            return
        }
        // A new setup becomes the one in use, so it can be filled in right away.
        if let added = config.setupNames.last, added == nameField, config.activeSetupName == before { config.activeSetupName = added }
        write(config)
        checker.reset()
        checker.reloadSetups()
        load()
        message = "Done."
    }
}
