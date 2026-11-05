import DeskUndoCore
import SwiftUI
import os

let log = Logger(subsystem: "io.github.marcellovictorino.desk-undo", category: "app")

@main
struct DeskUndoApp: App {
    @StateObject private var camera = CameraCheck()

    init() {
        do {
            let wrote = try ConfigLocation.ensureStarterFile()
            log.notice("config file \(ConfigLocation.file.path, privacy: .public) ready, created=\(wrote, privacy: .public)")
        } catch {
            log.error("config file not writable: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        MenuBarExtra("Desk Undo", systemImage: "arrow.uturn.backward.circle") {
            PopoverView(camera: camera)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

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
