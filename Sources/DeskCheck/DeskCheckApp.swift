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
        _ = ConfigLocation.load() // Creates only the default file when no file has been chosen.
        if let warning = ConfigLocation.settings.loadWarning { log.error("\(warning, privacy: .public)") }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(checker: checker)
        } label: {
            Image(nsImage: MenuBarIcon.image()).accessibilityLabel("Desk Check")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `open DeskCheck.app --args --check` runs one check at launch, the same as pressing
    /// Check desk; the numbers go to the unified log (subsystem io.github.marcellovictorino.desk-check).
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            PostureChecker.shared.refreshPermission()
            if CommandLine.arguments.contains("--check") {
                PostureChecker.shared.check()
            }
        }
    }
}
