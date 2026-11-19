import AppKit
import DeskCheckCore

/// Records the Live shortcut from the keys the person presses. While it listens, the current system-wide
/// combination is released and every key press is consumed, so nothing types into Settings or starts Live.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Why the last recording changed nothing, or what Esc and Delete do; empty when there is nothing to say.
    @Published private(set) var message = ""
    private var monitor: Any?

    func start(_ checker: PostureChecker) {
        guard !isRecording else { return }
        message = ""
        isRecording = true
        GlobalHotKey.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak checker] event in
            guard let self, let checker else { return event }
            MainActor.assumeIsolated { self.handle(event, checker) }
            return nil
        }
    }

    /// Ends a recording that changed nothing and puts the saved shortcut back.
    func cancel(_ checker: PostureChecker) {
        guard isRecording else { return }
        finish()
        checker.restoreLiveShortcut()
    }

    func clear(_ checker: PostureChecker) {
        if isRecording { finish() }
        message = checker.setLiveShortcut(nil) ?? ""
    }

    private func handle(_ event: NSEvent, _ checker: PostureChecker) {
        switch event.keyCode {
        case 53:  // Esc
            cancel(checker)
        case 51, 117:  // Delete, forward delete
            clear(checker)
        default:
            let flags = event.modifierFlags
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= KeyShortcut.command }
            if flags.contains(.shift) { modifiers |= KeyShortcut.shift }
            if flags.contains(.option) { modifiers |= KeyShortcut.option }
            if flags.contains(.control) { modifiers |= KeyShortcut.control }
            guard let shortcut = KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
                message = "Hold Control, Option, Shift or Command and press a letter, digit or Space."
                return
            }
            finish()
            message = checker.setLiveShortcut(shortcut) ?? ""
        }
    }

    private func finish() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
