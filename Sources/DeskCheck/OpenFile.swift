import AppKit

/// Opens a file in its default app. A plain text file such as the TOML config may have none, so TextEdit is the
/// fallback; `failed` runs when neither can open it.
func openWithTextEditFallback(_ file: URL, failed: @escaping @MainActor () -> Void) {
    if NSWorkspace.shared.open(file) { return }
    guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
        Task { @MainActor in failed() }
        return
    }
    NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        if error != nil { Task { @MainActor in failed() } }
    }
}
