import AppKit
import DeskCheckCore
import SwiftUI

/// The menu bar item and the panel it opens. This replaces SwiftUI's MenuBarExtra because that scene cannot be opened
/// from code, and a link, a command or a key combination has to open it. The panel hosts the same PopoverView.
@MainActor
final class PanelController: NSObject, NSPopoverDelegate {
    private let checker: PostureChecker
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var openAttempts = 0

    init(checker: PostureChecker) {
        self.checker = checker
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image()
        item.button?.setAccessibilityLabel("Desk Check")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(checker: checker))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        checker.live.popoverIsVisible = { [weak self] in self?.popover.isShown ?? false }
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    /// Opens the panel and brings it forward so it takes keys (Stop, Esc and Return work at once).
    func show() {
        guard let button = item?.button else { return }
        // Right after launch the status item has no place in the menu bar yet; try again shortly.
        if button.window?.frame.height ?? 0 == 0, openAttempts < 20 {
            openAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.show() }
            return
        }
        openAttempts = 0
        guard !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        checker.reloadSetups()
        checker.refreshPermission()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// `deskcheck://live`, `desk-check live` and the key combination: starts Live in the open panel, and the same
    /// request while Live runs stops it and closes the panel. While a check or calibration runs, only opens the panel.
    func toggleLive() {
        let live = checker.live
        if live.isRunning {
            live.stop()
            popover.performClose(nil)
            return
        }
        checker.showingSettings = false
        show()
        guard !checker.isBusy, checker.settingsWarning == nil else { return }
        // show() may be waiting for the status item; start Live once the panel is really up.
        startLiveWhenShown(attempts: 0)
    }

    private func startLiveWhenShown(attempts: Int) {
        if popover.isShown {
            if !checker.live.isRunning { checker.live.start() }
        } else if attempts < 30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.startLiveWhenShown(attempts: attempts + 1) }
        }
    }

    /// Reads `live_shortcut` from the settings file and registers it. Called at launch and whenever the panel opens.
    func refreshShortcut() {
        let config = checker.settings.load()
        let shortcut = config.liveShortcut
        if let text = config.liveShortcutText, shortcut == nil {
            log.error("live_shortcut \"\(text, privacy: .public)\" is not a key combination Desk Check understands")
        }
        GlobalHotKey.shared.register(shortcut) { [weak self] in self?.toggleLive() }
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) { refreshShortcut() }

    /// Clicking away, Esc on the main view or closing from code: Live stops and the camera turns off.
    func popoverDidClose(_ notification: Notification) {
        checker.clearPreview()
        checker.live.popoverHidden()
        // Next time the panel opens it starts on the main view, unless a calibration is still running.
        if !checker.isRunning && !checker.choosingSettingsFile { checker.showingSettings = false }
    }
}
