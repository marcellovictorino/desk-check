@preconcurrency import AVFoundation
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
    /// The panel is on its way up (the status item may not be laid out yet), with Live to start once it is. One
    /// operation, so a second request can cancel everything that is still waiting.
    private var opening: Task<Void, Never>?
    /// Counts camera permission prompts, so a delayed restore from an older one changes nothing.
    private var promptGeneration = 0

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
        checker.refreshLiveShortcut = { [weak self] in self?.refreshShortcut() ?? false }
        checker.live.popoverIsVisible = { [weak self] in self?.popover.isShown ?? false }
        // The system's camera permission prompt takes focus, which would close a transient popover and cancel Live
        // before it starts. Keep the panel open until the prompt is answered, then take the keys back.
        checker.live.permissionPrompt = { [weak self] prompting in
            guard let self else { return }
            log.notice("camera permission prompt \(prompting ? "may be showing" : "is over", privacy: .public)")
            promptGeneration += 1
            let generation = promptGeneration
            if prompting {
                // Only a first-use prompt takes focus; with access already decided nothing changes.
                guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
                popover.behavior = .applicationDefined
            } else if popover.behavior == .applicationDefined {
                // Answering the prompt hands focus back to whatever was in front before, a moment after this runs, which
                // would close a transient popover and cancel the Live that just started. Take the keys back first.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    // A newer prompt, or the panel closing meanwhile, owns the popover's behaviour now.
                    guard generation == promptGeneration, popover.isShown else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    popover.contentViewController?.view.window?.makeKey()
                    popover.behavior = .transient
                }
            }
        }
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    /// Opens the panel and brings it forward so it takes keys (Stop, Esc and Return work at once), then starts Live
    /// when asked. Right after launch the status item has no place in the menu bar yet, so it waits for one.
    func show(startingLive: Bool = false) {
        opening?.cancel()
        opening = Task { @MainActor in
            // A task cancelled before it first runs must change nothing, and must not clear a newer opening.
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if let button = item?.button, (button.window?.frame.height ?? 0) > 0 {
                    present(from: button)
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            opening = nil
            if startingLive, popover.isShown, !checker.live.isRunning { checker.live.start() }
        }
    }

    private func present(from button: NSStatusBarButton) {
        guard !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        checker.reloadSetups()
        checker.refreshPermission()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// `deskcheck://live`, `desk-check live` and the key combination: starts Live in the open panel, and the same
    /// request while Live runs, or while the panel is still opening for it, stops it and closes the panel. While a
    /// check or calibration runs, only opens the panel.
    func toggleLive() {
        let live = checker.live
        if live.isRunning || opening != nil {
            opening?.cancel()
            opening = nil
            live.stop()
            popover.performClose(nil)
            return
        }
        checker.showingSettings = false
        show(startingLive: !checker.isBusy && checker.settingsWarning == nil)
    }

    /// Reads `live_shortcut` from the settings file and registers it. Called at launch and whenever the panel opens.
    /// Returns false when macOS refused the combination, for example because another app holds it.
    @discardableResult
    func refreshShortcut() -> Bool {
        let config = checker.settings.load()
        // An unreadable file loads as the starter file, whose absent line would mean the default: register nothing
        // until the person's real file can be read, so a shortcut they switched off stays off.
        let readable = checker.settings.loadWarning == nil
        let shortcut = readable ? config.liveShortcut : nil
        if readable, let text = config.liveShortcutText, shortcut == nil {
            log.error("live_shortcut \"\(text, privacy: .public)\" is not a key combination Desk Check understands")
        }
        return GlobalHotKey.shared.register(shortcut) { [weak self] in self?.toggleLive() }
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) { refreshShortcut() }

    /// Clicking away, Esc on the main view or closing from code: Live stops and the camera turns off.
    func popoverDidClose(_ notification: Notification) {
        // Whatever closed the panel, it reopens as an ordinary transient popover.
        promptGeneration += 1
        popover.behavior = .transient
        opening?.cancel()
        opening = nil
        checker.clearPreview()
        checker.live.popoverHidden()
        // Next time the panel opens it starts on the main view, unless a calibration is still running.
        if !checker.isRunning && !checker.choosingSettingsFile { checker.showingSettings = false }
    }
}
