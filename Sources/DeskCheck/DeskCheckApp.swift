import AppKit
import DeskCheckCore
import SwiftUI
import os

let log = Logger(subsystem: "io.github.marcellovictorino.desk-check", category: "app")

@main
struct DeskCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = ConfigLocation.load()  // Creates only the default file when no file has been chosen.
        if let warning = ConfigLocation.settings.loadWarning { log.error("\(warning, privacy: .public)") }
    }

    /// The menu bar item and its panel belong to the app delegate (see PanelController); SwiftUI needs one scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PanelController?
    private var liveRequestedBeforeLaunch = false

    /// A deskcheck:// link that launches the app arrives before applicationDidFinishLaunching, so the handler is
    /// registered here.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: text), LiveLink.isLive(url)
        else { return }
        // Links that arrive before launch finishes keep toggle parity: two cancel each other.
        if let panel { panel.toggleLive() } else { liveRequestedBeforeLaunch.toggle() }
    }

    /// `open DeskCheck.app --args --check` runs one check at launch, the same as pressing
    /// Check desk; the numbers go to the unified log (subsystem io.github.marcellovictorino.desk-check).
    func applicationDidFinishLaunching(_ notification: Notification) {
        PostureChecker.shared.refreshPermission()
        let panel = PanelController(checker: PostureChecker.shared)
        self.panel = panel
        panel.refreshShortcut()
        if liveRequestedBeforeLaunch {
            liveRequestedBeforeLaunch = false
            panel.toggleLive()
        }
        if CommandLine.arguments.contains("--check") {
            PostureChecker.shared.check()
        }
    }
}
