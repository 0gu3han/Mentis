import AVFoundation
import Vision

final class ObjectClassifier: NSObject, ObservableObject {
    @Published var topLabel: String = ""
    @Published var confidence: Float = 0

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let classifyQueue = DispatchQueue(label: "com.mentis.classify", qos: .userInitiated)
    private var lastClassifyTime: Date = .distantPast
    private let classifyInterval: TimeInterval = 1.5
    private var isClassifying = false

    override init() {
        super.init()
        setupCamera()
    }

    func start() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
    }

    func stop() {
        captureSession.stopRunning()
    }

    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { captureSession.commitConfiguration(); return }

        captureSession.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: classifyQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }
        captureSession.commitConfiguration()
    }
}

extension ObjectClassifier: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastClassifyTime) >= classifyInterval, !isClassifying else { return }
        lastClassifyTime = now
        isClassifying = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isClassifying = false
            return
        }

        let request = VNClassifyImageRequest { [weak self] req, _ in
            defer { self?.isClassifying = false }
            guard
                let self,
                let results = req.results as? [VNClassificationObservation],
                let top = results.first(where: { $0.confidence > 0.25 && !Self.skipLabels.contains($0.identifier) })
            else { return }

            let label = (top.identifier
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "_", with: " ") ?? top.identifier)
                .capitalized

            DispatchQueue.main.async {
                self.topLabel = label
                self.confidence = top.confidence
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    // Skip overly generic Vision taxonomy labels
    private static let skipLabels: Set<String> = [
        "indoor", "outdoor", "nature", "abstract", "no person"
    ]
}
