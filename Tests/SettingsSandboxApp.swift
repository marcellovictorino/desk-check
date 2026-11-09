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
    }

    var body: some Scene {
        WindowGroup("Settings sandbox test") {
            PopoverView(checker: checker).content
                .environment(\.colorScheme, .light)
        }
        .windowResizability(.contentSize)
    }
}
