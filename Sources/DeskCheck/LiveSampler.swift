@preconcurrency import AVFoundation
import DeskCheckCore

/// Streams eye positions from the webcam until stopped. Every frame is analysed and dropped; only
/// the eye coordinates leave this class, and stopping closes the camera before `stop()` returns.
final class LiveSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let framesToSkip = 10
    /// Vision at full frame rate is wasteful; about ten readings a second is plenty for a one second average.
    static let minimumInterval = 0.1

    private let frameQueue = DispatchQueue(label: "desk-check.live.frames")
    private let sessionQueue = DispatchQueue(label: "desk-check.live.session")
    private let lock = NSLock()
    private var session: AVCaptureSession?
    private var framesSeen = 0
    private var lastAnalysed = 0.0
    private var stopped = false
    private let onEyes: @Sendable (EyePoints?, TimeInterval) -> Void

    /// `onEyes` gets the eyes found in a frame, or nil when the frame had no face, with its timestamp.
    init(onEyes: @escaping @Sendable (EyePoints?, TimeInterval) -> Void) { self.onEyes = onEyes }

    func start(device: AVCaptureDevice) throws {
        let session = AVCaptureSession()
        session.addInput(try AVCaptureDeviceInput(device: device))
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        session.addOutput(output)
        lock.withLock { self.session = session; stopped = false }
        sessionQueue.async { session.startRunning() }
    }

    func stop() {
        let session = lock.withLock { () -> AVCaptureSession? in stopped = true; defer { self.session = nil }; return self.session }
        guard let session else { return }
        // Waits for the camera to close, then for any frame still being analysed.
        sessionQueue.sync { session.stopRunning() }
        frameQueue.sync {}
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        let go = lock.withLock { () -> Bool in
            framesSeen += 1
            guard !stopped, framesSeen > Self.framesToSkip, now - lastAnalysed >= Self.minimumInterval else { return false }
            lastAnalysed = now
            return true
        }
        guard go, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        onEyes(FaceSampler.findEyes(in: pixels, size: size), now)
    }
}
