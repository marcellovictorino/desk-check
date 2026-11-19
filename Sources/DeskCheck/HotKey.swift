import Carbon.HIToolbox
import DeskCheckCore

/// One system-wide key combination, through Carbon's RegisterEventHotKey: it needs no Accessibility or Input
/// Monitoring permission and works inside the App Sandbox. Registering again replaces the earlier combination.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private var registered: KeyShortcut?

    /// Registers `shortcut` as an exclusive hot key, so another app holding the same combination makes this fail
    /// instead of both being notified, or removes the registration when it is nil. Returns false when macOS refused it.
    @discardableResult
    func register(_ shortcut: KeyShortcut?, action: @escaping () -> Void) -> Bool {
        self.action = action
        guard shortcut != registered || (shortcut != nil && ref == nil) else { return true }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = shortcut
        guard let shortcut else { return true }
        installHandlerOnce()
        let id = EventHotKeyID(signature: OSType(0x4465_6B43), id: 1)  // 'DekC'
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref)
        if status != noErr {
            ref = nil
            log.error("live_shortcut could not be registered (status \(status, privacy: .public))")
        }
        return status == noErr
    }

    /// Releases the current combination so that, while the person records a new one, pressing the old one does
    /// nothing. `register` or the panel's refresh puts a shortcut back.
    func pause() { register(nil) { [action] in action?() } }

    /// True when macOS itself uses the combination (an enabled entry in Keyboard Shortcuts), which Carbon would
    /// still let this app register without ever receiving it.
    static func isSystemShortcut(_ shortcut: KeyShortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return list.contains {
            ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && ($0[kHISymbolicHotKeyCode as String] as? Int) == Int(shortcut.keyCode)
                && ($0[kHISymbolicHotKeyModifiers as String] as? Int) == Int(shortcut.modifiers)
        }
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.shared.action?() } }
                return noErr
            }, 1, &spec, nil, &handler)
    }
}
