import AppKit

/// Opens a file in its default app. A plain text file such as the TOML config may have none, so TextEdit is the
/// fallback; `failed` runs when neither can open it. `release` runs once the open has finished, so a sandbox
/// permission held for the file lasts exactly as long as the other app needs it. A refusal for lack of permission
/// skips the fallback, which would only be refused too.
func openWithTextEditFallback(_ file: URL, release: @escaping () -> Void = {}, failed: @escaping @MainActor () -> Void) {
    if NSWorkspace.shared.open(file) {
        release()
        return
    }
    let refused = FileManager.default.fileExists(atPath: file.path) && !FileManager.default.isReadableFile(atPath: file.path)
    guard !refused,
        let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
    else {
        release()
        Task { @MainActor in failed() }
        return
    }
    NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        release()
        if error != nil { Task { @MainActor in failed() } }
    }
}
