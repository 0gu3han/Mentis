import AVFoundation
import CoreImage
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
    private let context = CIContext()

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
        captureSession.sessionPreset = .hd1920x1080
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

    // Crop the center 60% of the pixel buffer — matches the on-screen reticle
    private func cropCenter(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let full = CIImage(cvPixelBuffer: pixelBuffer)
        let w = full.extent.width
        let h = full.extent.height
        let cropW = w * 0.6
        let cropH = h * 0.6
        let cropRect = CGRect(x: (w - cropW) / 2, y: (h - cropH) / 2, width: cropW, height: cropH)
        let cropped = full.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(nil, Int(cropW), Int(cropH),
                            CVPixelBufferGetPixelFormatType(pixelBuffer), attrs as CFDictionary, &out)
        guard let result = out else { return nil }
        context.render(cropped, to: result)
        return result
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

        // Classify only the center crop (what the reticle is pointing at)
        let targetBuffer = cropCenter(pixelBuffer) ?? pixelBuffer

        let request = VNClassifyImageRequest { [weak self] req, _ in
            defer { self?.isClassifying = false }
            guard let self,
                  let results = req.results as? [VNClassificationObservation]
            else { return }

            // 1. Prefer a specific object label (any confidence > 0.1)
            // 2. Fall back to any non-scene label with confidence > 0.25
            let label = Self.bestLabel(from: results)
            guard let label else { return }

            DispatchQueue.main.async {
                self.topLabel = label.text
                self.confidence = label.confidence
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: targetBuffer, options: [:])
        try? handler.perform([request])
    }

    // MARK: - Label Selection

    private struct LabelResult {
        let text: String
        let confidence: Float
    }

    private static func bestLabel(from results: [VNClassificationObservation]) -> LabelResult? {
        // Walk results (sorted by confidence desc) and return the first
        // label that looks like a concrete object, not a scene descriptor.
        for result in results {
            let id = result.identifier
            if sceneLabels.contains(id) { continue }

            // Require a minimum confidence; specific objects need less
            let threshold: Float = objectLabels.contains(id) ? 0.12 : 0.30
            guard result.confidence >= threshold else { break } // sorted desc, no point continuing

            let text = id
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? id.capitalized

            return LabelResult(text: text, confidence: result.confidence)
        }
        return nil
    }

    // Generic scene / atmosphere labels — skip these entirely
    private static let sceneLabels: Set<String> = [
        "indoor", "outdoor", "nature", "abstract", "text",
        "day", "night", "sunrise", "sunset", "dusk", "dawn",
        "no person", "person", "one person", "group of persons", "selfie",
        "close-up", "macro", "aerial", "panoramic",
        "color", "black and white", "monochrome",
        "water", "sky", "ground", "floor", "wall", "ceiling",
        "dark", "bright", "blurry", "overexposed"
    ]

    // Known concrete object labels — accepted at lower confidence
    private static let objectLabels: Set<String> = [
        // Furniture
        "chair", "table", "sofa", "couch", "bed", "desk", "shelf", "cabinet",
        "bookcase", "wardrobe", "lamp", "pillow", "cushion", "curtain", "rug",
        // Electronics
        "laptop", "computer", "keyboard", "mouse", "monitor", "television", "tv",
        "phone", "smartphone", "tablet", "camera", "headphones", "speaker",
        "remote control", "microwave", "oven", "refrigerator", "toaster",
        // Vehicles
        "car", "truck", "bicycle", "motorcycle", "bus", "train", "airplane",
        "boat", "helicopter", "scooter",
        // Animals
        "dog", "cat", "bird", "fish", "horse", "cow", "sheep", "pig",
        "elephant", "bear", "tiger", "lion", "rabbit", "hamster",
        // Food & drink
        "apple", "banana", "orange", "pizza", "sandwich", "burger", "hot dog",
        "salad", "bread", "cake", "cookie", "coffee", "tea", "bottle", "cup",
        "bowl", "plate", "fork", "knife", "spoon", "glass",
        // Clothing / accessories
        "shirt", "pants", "shoes", "hat", "bag", "backpack", "glasses",
        "watch", "jacket", "dress", "sneaker", "boot",
        // Stationery / tools
        "book", "pen", "pencil", "notebook", "paper", "scissors", "ruler",
        "hammer", "screwdriver", "wrench", "key",
        // Nature objects
        "flower", "tree", "plant", "rock", "stone", "leaf",
        // Other common objects
        "ball", "toy", "candle", "clock", "picture frame", "mirror",
        "trash can", "box", "bag", "umbrella", "bicycle helmet", "bicycle wheel"
    ]
}
