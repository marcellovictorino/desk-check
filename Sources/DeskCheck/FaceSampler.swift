@preconcurrency import AVFoundation
import CoreImage
import DeskCheckCore
import Vision

/// A small copy of one frame for the optional preview, with the eye positions as fractions of its size
/// (origin top left). It lives in memory only while the popover shows it and is never written anywhere.
struct PreviewFrame {
    var image: CGImage
    var left: CGPoint
    var right: CGPoint
}

struct SampleResult {
    var cameraName: String
    var fieldOfViewDegrees: Double?
    var samples: [EyePoints]
}

/// Opens the webcam, finds the eyes in a number of frames with Apple's Vision face landmarks, and closes it.
/// Each frame is analysed and dropped; only the eye coordinates are kept.
final class FaceSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let framesToSkip = 10      // the camera adjusts exposure first
    static let samplesWanted = 15
    static let timeoutSeconds = 8.0

    // Frames arrive on `frameQueue`; the session starts, waits and stops on `sessionQueue`.
    // They must differ, or the wait blocks frame delivery.
    private let frameQueue = DispatchQueue(label: "desk-check.camera.frames")
    private let sessionQueue = DispatchQueue(label: "desk-check.camera.session")
    private let lock = NSLock()
    private let enough = DispatchSemaphore(value: 0)
    private let ciContext = CIContext()
    private var samples: [EyePoints] = []
    private var framesSeen = 0
    private var signalled = false
    /// Set once the result is delivered; later frames are dropped, so nothing is read after the result.
    private var finished = false
    private var startedAt = 0.0
    private let wantPreview: Bool
    private let onPreview: @Sendable (PreviewFrame) -> Void

    init(wantPreview: Bool, onPreview: @escaping @Sendable (PreviewFrame) -> Void) {
        self.wantPreview = wantPreview
        self.onPreview = onPreview
    }

    static func connectedCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera], mediaType: .video,
                                         position: .unspecified).devices
    }

    /// The camera a setup asks for, if it is connected. "auto" prefers an external webcam.
    static func camera(for choice: CameraChoice) -> AVCaptureDevice? {
        let all = connectedCameras()
        switch choice {
        case .auto: return all.first { $0.deviceType == .external } ?? all.first
        case .builtIn: return all.first { $0.deviceType == .builtInWideAngleCamera }
        case .named(let name): return all.first { $0.localizedName == name }
        }
    }

    /// `completion` gets the result as soon as it is ready; `onStopped` follows once the camera is really off, and is not
    /// called when the camera could not open.
    func run(device: AVCaptureDevice, completion: @escaping @Sendable (SampleResult?, String?) -> Void,
             onStopped: @escaping @Sendable () -> Void) {
        let session = AVCaptureSession()
        do {
            session.addInput(try AVCaptureDeviceInput(device: device))
        } catch {
            completion(nil, "The camera could not open: \(error.localizedDescription)")
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        session.addOutput(output)
        let name = device.localizedName
        sessionQueue.async {
            self.lock.withLock { self.startedAt = ProcessInfo.processInfo.systemUptime }
            session.startRunning()
            log.notice("camera timing: started after \(self.elapsedMs(), privacy: .public) ms")
            _ = self.enough.wait(timeout: .now() + Self.timeoutSeconds)
            // Deliver the result first, then close the camera: closing a USB webcam is slow and the answer does not need it.
            let result = self.lock.withLock { () -> SampleResult in
                self.finished = true
                return SampleResult(cameraName: name, fieldOfViewDegrees: nil, samples: self.samples)
            }
            log.notice("camera timing: result after \(self.elapsedMs(), privacy: .public) ms, samples=\(result.samples.count, privacy: .public)")
            completion(result, nil)
            session.stopRunning()
            log.notice("camera timing: stopped after \(self.elapsedMs(), privacy: .public) ms")
            onStopped()
        }
    }

    private func elapsedMs() -> Int { Int((ProcessInfo.processInfo.systemUptime - lock.withLock { startedAt }) * 1000) }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let (seen, done) = lock.withLock { () -> (Int, Bool) in framesSeen += 1; return (framesSeen, finished) }
        if seen == 1 { log.notice("camera timing: first frame after \(self.elapsedMs(), privacy: .public) ms") }
        guard !done, seen > Self.framesToSkip, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        guard let eyes = Self.findEyes(in: pixels, size: size) else { return }
        let count = lock.withLock { () -> Int in
            if !finished, samples.count < Self.samplesWanted { samples.append(eyes) }
            return samples.count
        }
        if wantPreview, seen % 2 == 0, !lock.withLock({ finished }) { sendPreview(pixels, eyes: eyes, size: size) }
        if count >= Self.samplesWanted {
            let first = lock.withLock { () -> Bool in defer { signalled = true }; return !signalled }
            if first {
                log.notice("camera timing: enough samples after \(self.elapsedMs(), privacy: .public) ms")
                enough.signal()
            }
        }
    }

    static func findEyes(in pixels: CVPixelBuffer, size: CGSize) -> EyePoints? {
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request]) } catch { return nil }
        guard let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let landmarks = face.landmarks else { return nil }
        func centre(_ region: VNFaceLandmarkRegion2D?) -> EyePoints.Point? {
            guard let points = region?.pointsInImage(imageSize: size), !points.isEmpty else { return nil }
            let n = Double(points.count)
            return .init(x: points.reduce(0) { $0 + Double($1.x) } / n, y: points.reduce(0) { $0 + Double($1.y) } / n)
        }
        guard let left = centre(landmarks.leftPupil) ?? centre(landmarks.leftEye),
              let right = centre(landmarks.rightPupil) ?? centre(landmarks.rightEye) else { return nil }
        return EyePoints(left: left, right: right, imageWidth: size.width, imageHeight: size.height,
                         yaw: face.yaw?.doubleValue ?? 0)
    }

    private func sendPreview(_ pixels: CVPixelBuffer, eyes: EyePoints, size: CGSize) {
        let scale = 320 / size.width
        let small = CIImage(cvPixelBuffer: pixels).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = ciContext.createCGImage(small, from: small.extent) else { return }
        func point(_ p: EyePoints.Point) -> CGPoint { CGPoint(x: p.x / size.width, y: 1 - p.y / size.height) }
        onPreview(PreviewFrame(image: image, left: point(eyes.left), right: point(eyes.right)))
    }
}
