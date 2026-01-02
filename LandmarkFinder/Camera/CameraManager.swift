import AVFoundation
import UIKit

final class CameraManager: NSObject {
    let session = AVCaptureSession()

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames.queue")
    private var onFrame: ((UIImage) -> Void)?

    enum CameraError: LocalizedError {
        case unauthorized
        case noDevice
        case cannotAddInput
        case cannotAddOutput
        case simulatorNotSupported

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Camera permission denied"
            case .noDevice: return "No camera device available"
            case .cannotAddInput: return "Cannot create camera input"
            case .cannotAddOutput: return "Cannot add camera output"
            case .simulatorNotSupported: return "Camera not supported on Simulator"
            }
        }
    }

    func start(onFrame: @escaping (UIImage) -> Void) throws {
        self.onFrame = onFrame

        #if targetEnvironment(simulator)
        throw CameraError.simulatorNotSupported
        #else
        // Check authorization
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            // Synchronously request for simplicity; you can refactor to async if preferred.
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted = ok
                semaphore.signal()
            }
            semaphore.wait()
            guard granted else { throw CameraError.unauthorized }

        case .authorized:
            break

        case .denied, .restricted:
            throw CameraError.unauthorized

        @unknown default:
            throw CameraError.unauthorized
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noDevice
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                let desiredAngle: CGFloat = 90
                if connection.isVideoRotationAngleSupported(desiredAngle) {
                    connection.videoRotationAngle = desiredAngle
                } else if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

        session.startRunning()
        #endif
    }

    func stop() {
        session.stopRunning()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        onFrame?(uiImage)
    }
}
