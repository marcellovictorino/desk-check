import DeskCheckCore
import AppKit
import SwiftUI
import os

let log = Logger(subsystem: "io.github.marcellovictorino.desk-check", category: "app")

@main
struct DeskCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var checker = PostureChecker.shared

    init() {
        do {
            let wrote = try ConfigLocation.ensureStarterFile()
            log.notice("config file \(ConfigLocation.file.path, privacy: .public) ready, created=\(wrote, privacy: .public)")
        } catch {
            log.error("config setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(checker: checker)
        } label: {
            Image(nsImage: MenuBarIcon.image()).accessibilityLabel("Desk Check")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(checker: checker)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `open DeskCheck.app --args --check` runs one check at launch, the same as pressing
    /// Check desk; the numbers go to the unified log (subsystem io.github.marcellovictorino.desk-check).
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opening Settings makes the app a regular one so its window can come to the front; closing it goes back to menu bar only.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, window.styleMask.contains(.titled), !(window is NSPanel) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
        Task { @MainActor in
            PostureChecker.shared.refreshPermission()
            if CommandLine.arguments.contains("--check") {
                PostureChecker.shared.check()
            }
        }
    }
}
