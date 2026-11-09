import AppKit
import QuartzCore
import SwiftUI
import XCTest
import DeskCheckCore
@testable import DeskCheck

/// Intent source: save offscreen pictures of the popover, Live and Settings for cards.
/// The follow-up explicitly permits partial pictures if each labels its omissions.
final class ViewImageTests: XCTestCase {
    private struct Capture: Codable {
        let file: String
        let renderer: String
        let limitation: String
    }

    @MainActor
    func testSaveLabelledPartialViewImagesOffscreen() async throws {
        // Never activate the app, create a menu bar item, order a window in, or start the camera.
        let app = NSApplication.shared
        let appearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = appearance }
        let config = DeskConfig(text: DeskConfig.starterContents)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("desk-check-view-\(UUID().uuidString)/config.toml")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "desk-check-view-tests.\(UUID().uuidString)"))
        let settingsFile = SettingsFile(defaultFile: fixture, defaults: defaults)
        try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.document.text.write(to: fixture, atomically: false, encoding: .utf8)
        let checker = PostureChecker(settings: settingsFile)
        let live = checker.live
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["DESK_CHECK_IMAGE_DIR"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("desk-check-images-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let popover = Capture(file: "popover.png", renderer: "SwiftUI ImageRenderer",
            limitation: "No outer popover chrome or desktop backdrop; native glass fidelity is unverified. Camera and permission checks are not run.")
        let liveCapture = Capture(file: "live.png", renderer: "SwiftUI ImageRenderer",
            limitation: "No outer popover chrome or desktop backdrop; native glass fidelity is unverified. Camera off: no live readings or coloured bands.")
        let settings = Capture(file: "settings.png", renderer: "NSView cacheDisplay",
            limitation: "Native glass button surfaces and some icons are omitted. Initial scroll position only: lower fields and outer popover chrome are omitted.")
        try await save(PopoverView(checker: checker).content, capture: popover,
                       title: "Popover", width: 320, swiftUI: true, to: directory)
        try await save(LiveView(live: live).padding(14).frame(width: 320), capture: liveCapture,
                       title: "Live", width: 320, swiftUI: true, to: directory)
        checker.showingSettings = true
        try await save(PopoverView(checker: checker), capture: settings,
                       title: "Settings", width: 520, swiftUI: false, to: directory)
        // Intent: a failed settings load is visible in both entry points, not hidden behind starter settings.
        let missingFile = SettingsFile(defaultFile: fixture.deletingLastPathComponent().appendingPathComponent("missing.toml"), defaults: defaults)
        let warningChecker = PostureChecker(settings: missingFile)
        XCTAssertNotNil(warningChecker.settingsWarning)
        let warning = Capture(file: "load-warning.png", renderer: "SwiftUI ImageRenderer",
            limitation: popover.limitation)
        try await save(PopoverView(checker: warningChecker).content, capture: warning,
                       title: "Settings load warning", width: 320, swiftUI: true, to: directory)
        warningChecker.showingSettings = true
        let warningSettings = Capture(file: "settings-warning.png", renderer: "NSView cacheDisplay",
            limitation: settings.limitation)
        try await save(PopoverView(checker: warningChecker).content, capture: warningSettings,
                       title: "Settings load warning", width: 520, swiftUI: false, to: directory)
        XCTAssertFalse(warningChecker.isRunning)
        XCTAssertTrue(checker.showingSettings)
        XCTAssertFalse(checker.isRunning)
        XCTAssertFalse(live.isRunning)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([popover, liveCapture, settings, warning, warningSettings])
            .write(to: directory.appendingPathComponent("captures.json"), options: .withoutOverwriting)
        print("Desk Check partial view images: \(directory.path)")
    }

    @MainActor
    private func save<V: View>(_ view: V, capture: Capture, title: String, width: CGFloat,
                               swiftUI: Bool, to directory: URL) async throws {
        let content = view.environment(\.colorScheme, .light).background(Color.white)
        let host = NSHostingView(rootView: content)
        // A real backing store, kept ordered out, initialises native controls without touching the screen.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderOut(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        XCTAssertEqual(size.width, width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 100)
        host.setFrameSize(size)
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        await Task.yield()
        host.displayIfNeeded()
        CATransaction.flush()
        let bitmap: NSBitmapImageRep
        if swiftUI {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
            renderer.scale = 2
            bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        } else {
            bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        // This only rejects a uniform/blank content area, not missing controls or incorrect glass.
        // Check before adding the caption: a caption alone must not make a blank render pass.
        let colours = Set(stride(from: 0, to: bitmap.pixelsHigh, by: 4).flatMap { y in
            stride(from: 0, to: bitmap.pixelsWide, by: 4).compactMap { x in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.description
            }
        })
        XCTAssertGreaterThan(colours.count, 16, "\(title): expected non-uniform partial content, not full visual fidelity")
        let labelled = try label(bitmap, size: size, text: "Partial offscreen render: \(title)\n\(capture.limitation)")
        let file = directory.appendingPathComponent(capture.file)
        try XCTUnwrap(labelled.representation(using: .png, properties: [:]))
            .write(to: file, options: .withoutOverwriting)
        let saved = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: file)))
        XCTAssertEqual(saved.pixelsWide, bitmap.pixelsWide)
        XCTAssertEqual(saved.pixelsHigh, labelled.pixelsHigh)
        XCTAssertGreaterThan(saved.pixelsHigh, bitmap.pixelsHigh, "Every partial picture carries its omission caption")
        XCTAssertFalse(window.isVisible, "Rendering must never show a window")
        XCTAssertFalse(window.isKeyWindow, "Rendering must never take keyboard focus")
        print("\(capture.file): \(capture.limitation)")
    }

    @MainActor
    private func label(_ bitmap: NSBitmapImageRep, size: CGSize, text: String) throws -> NSBitmapImageRep {
        let caption = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray
        ])
        let captionHeight = ceil(caption.boundingRect(with: CGSize(width: size.width - 24, height: .greatestFiniteMagnitude),
                                                     options: .usesLineFragmentOrigin).height)
        let footerHeight = captionHeight + 24
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let labelled = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: bitmap.pixelsWide, pixelsHigh: Int(ceil((size.height + footerHeight) * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: labelled))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height + footerHeight).fill()
        bitmap.draw(in: NSRect(x: 0, y: footerHeight, width: size.width, height: size.height))
        NSColor(white: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: footerHeight).fill()
        caption.draw(with: NSRect(x: 12, y: 12, width: size.width - 24, height: captionHeight),
                     options: .usesLineFragmentOrigin)
        return labelled
    }
}
