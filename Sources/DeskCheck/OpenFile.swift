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
    let refused = isPermissionDenied(file)
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

/// Whether opening the file fails for lack of permission. Unlike a stat-based check, which cannot tell a denied file
/// from a missing one, this reads the error the system gives.
private func isPermissionDenied(_ file: URL) -> Bool {
    do {
        try FileHandle(forReadingFrom: file).close()
        return false
    } catch {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return [error, underlying].compactMap { $0 }.contains {
            ($0.domain == NSCocoaErrorDomain && $0.code == CocoaError.fileReadNoPermission.rawValue)
                || ($0.domain == NSPOSIXErrorDomain && ($0.code == Int(EACCES) || $0.code == Int(EPERM)))
        }
    }
}
