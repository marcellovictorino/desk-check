import DeskUndoCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var camera: CameraCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desk Undo").font(.headline)
            Text("Camera permission: \(camera.permissionText)")
                .font(.callout)
            Text(camera.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Test camera") { camera.run() }
                    .disabled(camera.isRunning)
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { camera.refreshPermission() }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Config file", value: ConfigLocation.file.path)
            Text("Measurements arrive in the next version.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
