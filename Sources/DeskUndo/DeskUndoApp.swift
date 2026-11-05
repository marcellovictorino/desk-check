import DeskUndoCore
import SwiftUI
import os

let log = Logger(subsystem: "io.github.marcellovictorino.desk-undo", category: "app")

@main
struct DeskUndoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var camera = CameraCheck.shared

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `open DeskUndo.app --args --check-camera` runs one camera check at launch,
    /// the same as pressing Test camera, so the check can be tried from a script.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            CameraCheck.shared.refreshPermission()
            if CommandLine.arguments.contains("--check-camera") {
                CameraCheck.shared.run()
            }
        }
    }
}
