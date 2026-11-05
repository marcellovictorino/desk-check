@preconcurrency import AVFoundation
import SwiftUI

/// Opens the webcam for about two seconds, counts the frames it delivers and closes it.
/// Frames are dropped as they arrive: no image is kept in memory or written anywhere.
@MainActor
final class CameraCheck: NSObject, ObservableObject {
    @Published private(set) var permissionText = "unknown"
    @Published private(set) var statusText = "The camera is off."
    @Published private(set) var isRunning = false

    private let queue = DispatchQueue(label: "desk-undo.camera")
    private let counter = FrameCounter()
    private var session: AVCaptureSession?

    func refreshPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionText = Self.describe(status)
        log.notice("camera permission \(self.permissionText, privacy: .public)")
    }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.refreshPermission()
                guard granted else {
                    self.statusText = "Desk Undo has no camera permission. Allow it in System Settings, Privacy & Security, Camera."
                    self.isRunning = false
                    return
                }
                self.startSession()
            }
        }
    }

    private func startSession() {
        guard let device = Self.preferredCamera() else {
            statusText = "No camera found."
            isRunning = false
            return
        }
        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)
        } catch {
            statusText = "The camera could not open: \(error.localizedDescription)"
            isRunning = false
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(counter, queue: queue)
        session.addOutput(output)
        counter.reset()
        self.session = session
        statusText = "Camera on: \(device.localizedName)…"
        let name = device.localizedName
        log.notice("camera session starting on \(name, privacy: .public)")
        queue.async {
            session.startRunning()
            Thread.sleep(forTimeInterval: 2)
            session.stopRunning()
            let frames = self.counter.count
            Task { @MainActor in
                self.session = nil
                self.isRunning = false
                self.statusText = "Camera worked: \(frames) frames from \(name). The camera is off."
                log.notice("camera session stopped, frames=\(frames, privacy: .public)")
            }
        }
    }

    /// Prefers an external webcam, which is what Desk Undo is designed for.
    static func preferredCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first { $0.deviceType == .external } ?? discovery.devices.first
    }

    static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "allowed"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }
}

private final class FrameCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0

    var count: Int { lock.withLock { frames } }
    func reset() { lock.withLock { frames = 0 } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock { frames += 1 }
    }
}
