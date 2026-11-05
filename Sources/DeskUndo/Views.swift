import DeskUndoCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var checker: PostureChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desk Undo").font(.headline)
            if let preview = checker.preview { PreviewView(frame: preview) }
            if let r = checker.reading {
                ForEach(Array(checker.advice.enumerated()), id: \.offset) { _, item in
                    Label(item.sentence, systemImage: item.status == .good ? "checkmark.circle.fill" : "arrow.up.and.down.circle.fill")
                        .foregroundStyle(item.status == .good ? Color.green : Color.orange)
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
        .onAppear { checker.refreshPermission() }
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
    @State private var fields = Fields()
    @State private var showPreview = false
    @State private var saved = ""

    struct Fields {
        var distance = "", screenTop = "", lens = "", height = "", seatedEye = ""
    }

    var body: some View {
        Form {
            Section("Tape measure (centimetres)") {
                field("Eye to screen, seated", $fields.distance, hint: "for calibration")
                field("Top of screen above desk", $fields.screenTop, hint: "default \(Int(Setup.defaultScreenTopHeightCm))")
                field("Webcam lens above screen top", $fields.lens, hint: "default \(Int(Setup.defaultLensOffsetCm))")
                field("Your height", $fields.height, hint: "default \(Int(Setup.defaultUserHeightCm))")
                field("Seated eyes above desk", $fields.seatedEye, hint: "estimated from height")
                Text("Leave a field empty to use the default estimate.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Webcam") {
                Text(checker.webcamName ?? "No camera found")
                Text("Sit as you normally do with your eyes at the tape distance, then calibrate. This teaches Desk Undo your webcam's field of view and tilt.")
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
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                Text(saved).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Config file", value: ConfigLocation.file.path).font(.caption)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { load(); checker.refreshPermission() }
    }

    private var calibrationSummary: String {
        guard let name = checker.webcamName else { return "" }
        let c = ConfigLocation.load().calibration(forWebcam: name)
        guard let f = c.focalWidths else { return "Not calibrated: distances use the webcam's reported field of view." }
        return String(format: "Calibrated: focal length %.3f image widths, tilt %.1f°.", f, c.pitchDegrees ?? 0)
    }

    private func field(_ label: String, _ text: Binding<String>, hint: String) -> some View {
        LabeledContent(label) {
            TextField("", text: text, prompt: Text(hint)).multilineTextAlignment(.trailing).frame(width: 140)
        }
    }

    private func load() {
        let config = ConfigLocation.load()
        let s = config.setup
        func str(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "" }
        fields = Fields(distance: str(s.screenDistanceCm), screenTop: str(s.screenTopHeightCm), lens: str(s.lensOffsetCm),
                        height: str(s.userHeightCm), seatedEye: str(s.seatedEyeHeightCm))
        showPreview = config.showPreview
    }

    private func save() {
        func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        var config = ConfigLocation.load()
        config.setup = Setup(screenDistanceCm: num(fields.distance), screenTopHeightCm: num(fields.screenTop),
                             lensOffsetCm: num(fields.lens), userHeightCm: num(fields.height), seatedEyeHeightCm: num(fields.seatedEye))
        config.showPreview = showPreview
        do {
            try ConfigLocation.save(config)
            saved = "Saved."
        } catch {
            saved = "Could not save: \(error.localizedDescription)"
        }
    }
}
