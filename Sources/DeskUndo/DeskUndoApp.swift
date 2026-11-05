import DeskUndoCore
import SwiftUI
import os

let log = Logger(subsystem: "io.github.marcellovictorino.desk-undo", category: "app")

@main
struct DeskUndoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var checker = PostureChecker.shared

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
            PopoverView(checker: checker)
        }
        .menuBarExtraStyle(.window)

        Window("Live adjustment", id: "live") {
            LiveView(live: LiveController.shared)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(checker: checker)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `open DeskUndo.app --args --check` runs one check at launch, the same as pressing
    /// Check posture; the numbers go to the unified log (subsystem io.github.marcellovictorino.desk-undo).
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            PostureChecker.shared.refreshPermission()
            if CommandLine.arguments.contains("--check") {
                PostureChecker.shared.check()
            }
        }
    }
}
