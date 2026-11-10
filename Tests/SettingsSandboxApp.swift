// Intent: exercise the real Settings file picker and security-scoped access without personal settings or a camera.
// Compile with the app sources (except DeskCheckApp.swift) and DeskCheckCore, then sign with the app entitlements.
import AppKit
import DeskCheckCore
import SwiftUI
import os

let log = Logger(subsystem: "desk-check.settings-sandbox-test", category: "test")

@main
struct SettingsSandboxApp: App {
    @StateObject private var checker: PostureChecker

    init() {
        // This app has a disposable bundle identity, so Application Support and preferences are isolated.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SettingsSandboxTest", isDirectory: true)
        let file = directory.appendingPathComponent("config.toml")
        let settings = SettingsFile(defaultFile: file, defaults: .standard) {
            if !FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try DeskConfig.starterContents.write(to: file, atomically: false, encoding: .utf8)
            }
        }
        let checker = PostureChecker(settings: settings)
        checker.showingSettings = true
        _checker = StateObject(wrappedValue: checker)
        SnapshotOnSignal.install()
    }

    var body: some Scene {
        WindowGroup("Settings sandbox test") {
            PopoverView(checker: checker).content
        }
        .windowResizability(.contentSize)
    }
}

/// Intent: let a test runner photograph this window without screen recording permission.
/// Each SIGUSR1 saves the window's own bitmap as snapshot-N.png in the container's SettingsSandboxTest/snapshots folder.
enum SnapshotOnSignal {
    private static var source: DispatchSourceSignal?
    private static var count = 0

    static func install() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SettingsSandboxTest/snapshots", isDirectory: true)
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler {
            // Render the layer tree: SwiftUI text lives in layers that cacheDisplay leaves out.
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Settings sandbox test" }),
                  let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else { return }
            let scale = window.backingScaleFactor
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                                                pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return }
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            count += 1
            let file = folder.appendingPathComponent("snapshot-\(count).png")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(to: file)
            }
            catch { log.error("Snapshot failed: \(error.localizedDescription, privacy: .public)") }
        }
        source.resume()
        Self.source = source
    }
}
