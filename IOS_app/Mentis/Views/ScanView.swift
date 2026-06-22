import SwiftUI
import UIKit
import ARKit
import SceneKit
import RealityKit

struct ScanView: View {
    @Environment(\.dismiss) var dismiss
    @State private var roomName        = ""
    @State private var phase: Phase    = .naming
    @State private var errorMessage:   String?

    // ARKit mesh scan state
    @State private var finishRequested = false
    @State private var isProcessing    = false
    @State private var meshCount       = 0
    @State private var coveredCount    = 0
    @State private var meshProgress:   Double = 0
    @State private var scanStartTime:  Date?
    @State private var scanElapsed:    Double = 0
    @State private var scanTipIndex:   Int = 0
    @State private var tipTimer:       Timer? = nil

    private static let scanTips = [
        "Move slowly around the entire room",
        "Get within 30 cm of books, screens, and objects on tables",
        "Tilt phone sideways to capture vertical faces of objects",
        "Scan from below shelf level to capture object sides",
        "Cover all walls, corners, and furniture surfaces",
        "Revisit objects — closer pass = denser mesh",
    ]
    private let minScanSeconds: Double = 20

    // Photogrammetry state
    @State private var sampleDir:          URL?
    @State private var frameCount:         Int    = 0
    @State private var photoMeshCount:     Int    = 0
    @State private var processingProgress: Double = 0

    private let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    private var hasPhotogrammetry: Bool {
        if #available(iOS 17, *) { return PhotogrammetrySession.isSupported }
        return false
    }

    enum Phase { case naming, capturing, scanning, processing, uploading, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mSurface.ignoresSafeArea()
                switch phase {
                case .naming:              namingView
                case .capturing:           capturingView
                case .scanning:            scanningView
                case .processing:          processingView
                case .uploading, .done:    statusView
                }
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cleanupAndDismiss() }
                        .foregroundStyle(Color.mSecondary)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} }
            message: { Text(errorMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Naming

    private var namingView: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ROOM NAME")
                        .font(.mLabel()).tracking(0.8)
                        .foregroundStyle(Color.mSecondary)
                    TextField("e.g. Bedroom, Office", text: $roomName)
                        .sinkStyle()
                }

                HStack(spacing: 10) {
                    Image(systemName: hasLiDAR ? "sensor.tag.radiowaves.forward.fill" : "arkit")
                        .foregroundStyle(hasLiDAR ? Color.mSecondaryFixedDim : Color.mPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasLiDAR ? "3D Mesh Scan" : "AR Placement Mode")
                            .font(.mLabel(12)).tracking(0.3)
                            .foregroundStyle(Color.mOnSurface)
                        Text(hasLiDAR
                             ? "LiDAR detected — captures a real-color 3D mesh"
                             : "No LiDAR — place anchors in your real space using AR")
                            .font(.mLabel(11))
                            .foregroundStyle(Color.mSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(Color.mSurfaceContainerHigh,
                             in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            MentisPrimaryButton(
                title: hasLiDAR ? "Start 3D Scan" : "Create Room",
                isLoading: false
            ) { startCreation() }
                .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(roomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Capturing (Photogrammetry frame collection)

    private var capturingView: some View {
        ZStack(alignment: .bottom) {
            if let dir = sampleDir {
                PhotogrammetryCaptureRepresentable(
                    sampleDir: dir,
                    onFrameCount:  { frameCount      = $0 },
                    onMeshUpdated: { photoMeshCount  = $0 }
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(frameCount >= 15 ? Color.mSecondaryFixedDim : Color.mSecondary)
                            .frame(width: 6, height: 6)
                        Text(frameCount < 15
                             ? "\(frameCount) frames — keep moving (need 15+)"
                             : "\(frameCount) frames captured")
                            .font(.mLabel(11)).tracking(0.4)
                            .foregroundStyle(frameCount >= 15 ? Color.mSecondaryFixedDim : Color.mSecondary)
                    }
                    if photoMeshCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.cyan.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Text("\(photoMeshCount) surfaces")
                                .font(.mLabel(11)).tracking(0.4)
                                .foregroundStyle(Color.cyan.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.mSurfaceContainerHighest.opacity(0.9), in: Capsule())

                HStack(spacing: 12) {
                    Text("Move slowly — cover all walls & angles")
                        .font(.mLabel(12))
                        .foregroundStyle(Color.mOnSurface)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.mSurfaceContainerHigh.opacity(0.85), in: Capsule())

                    Button {
                        phase = .processing
                        if #available(iOS 17, *) {
                            Task { await runPhotogrammetry() }
                        }
                    } label: {
                        Text("Finish")
                            .font(.mLabel(13)).tracking(0.3)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(.mGradient, in: Capsule())
                    }
                    .disabled(frameCount < 15)
                    .opacity(frameCount < 15 ? 0.4 : 1)
                }
            }
            .padding(.bottom, 52)
        }
    }

    // MARK: - Scanning (ARKit mesh — fallback)

    private var canFinishScan: Bool { scanElapsed >= minScanSeconds }

    private var scanningView: some View {
        ZStack(alignment: .bottom) {
            MeshScanRepresentable(
                finishRequested:   $finishRequested,
                onMeshUpdated:     { count in meshCount    = count },
                onCoverageUpdated: { count in coveredCount = count },
                onProgress:        { p in meshProgress = p },
                onExported:        { url in Task { await upload(fileURL: url) } }
            )
            .ignoresSafeArea()
            .onAppear {
                scanStartTime = Date()
                scanElapsed   = 0
                tipTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    scanElapsed = Date().timeIntervalSince(scanStartTime ?? Date())
                    if Int(scanElapsed) % 4 == 0 {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            scanTipIndex = (scanTipIndex + 1) % ScanView.scanTips.count
                        }
                    }
                }
            }
            .onDisappear { tipTimer?.invalidate(); tipTimer = nil }

            if isProcessing {
                Color.mSurface.opacity(0.88).ignoresSafeArea()
                VStack(spacing: 16) {
                    if meshProgress > 0 {
                        ProgressView(value: meshProgress)
                            .tint(Color.mSecondaryFixedDim)
                            .padding(.horizontal, 40)
                        Text("Colorizing mesh… \(Int(meshProgress * 100))%")
                            .font(.mLabel()).tracking(0.5)
                            .foregroundStyle(Color.mSecondaryFixedDim)
                    } else {
                        ProgressView().tint(Color.mSecondaryFixedDim).scaleEffect(1.5)
                        Text("Building 3D model…")
                            .font(.mLabel()).tracking(0.5)
                            .foregroundStyle(Color.mSecondary)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    if meshCount > 0 {
                        HStack(spacing: 10) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.mSecondaryFixedDim.opacity(0.5))
                                    .frame(width: 5, height: 5)
                                Text("\(meshCount) surfaces")
                                    .font(.mLabel(10)).tracking(0.3)
                                    .foregroundStyle(Color.mSecondaryFixedDim.opacity(0.8))
                            }
                            if coveredCount > 0 {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.85, blue: 0.4))
                                        .frame(width: 5, height: 5)
                                    Text("\(coveredCount) scanned ✓")
                                        .font(.mLabel(10)).tracking(0.3)
                                        .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.4))
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.mSurfaceContainerHighest.opacity(0.9), in: Capsule())
                    }

                    HStack(spacing: 12) {
                        Text(ScanView.scanTips[scanTipIndex])
                            .font(.mLabel(12))
                            .foregroundStyle(Color.mOnSurface)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.mSurfaceContainerHigh.opacity(0.85), in: Capsule())
                            .transition(.opacity)
                            .id(scanTipIndex)

                        Button {
                            meshProgress    = 0
                            isProcessing    = true
                            finishRequested = true
                        } label: {
                            Text("Finish Scan")
                                .font(.mLabel(13)).tracking(0.3)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(canFinishScan ? AnyShapeStyle(.mGradient) : AnyShapeStyle(Color.mSecondary.opacity(0.4)), in: Capsule())
                        }
                        .disabled(!canFinishScan)
                    }

                    if !canFinishScan {
                        let remaining = Int(minScanSeconds - scanElapsed)
                        Text("Keep scanning… \(remaining)s")
                            .font(.mLabel(10)).tracking(0.3)
                            .foregroundStyle(Color.mOutlineVariant)
                    }
                }
                .padding(.bottom, 52)
            }
        }
    }

    // MARK: - Processing (Photogrammetry on-device)

    private var processingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.mPrimaryContainer.opacity(0.3))
                    .frame(width: 80, height: 80)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.mPrimary)
            }
            ProgressView(value: processingProgress)
                .tint(Color.mPrimary)
                .padding(.horizontal, 40)
            Text("Building 3D model… \(Int(processingProgress * 100))%")
                .font(.mLabel()).tracking(0.5)
                .foregroundStyle(Color.mSecondary)
            Text("This may take several minutes")
                .font(.mLabel(11))
                .foregroundStyle(Color.mOutlineVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Status (uploading / done)

    private var statusView: some View {
        VStack(spacing: 20) {
            if phase == .uploading {
                ProgressView().tint(Color.mPrimary).scaleEffect(1.5)
                Text("Uploading to server…")
                    .font(.mLabel()).tracking(0.5)
                    .foregroundStyle(Color.mSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.mSecondaryFixedDim)
                Text("Room Created!")
                    .font(.mTitle(22)).foregroundStyle(Color.mOnSurface)
                Text("Enter AR mode to place your anchors.")
                    .font(.mBody()).foregroundStyle(Color.mSecondary)
                    .multilineTextAlignment(.center)
                MentisPrimaryButton(title: "Done", isLoading: false) { dismiss() }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startCreation() {
        if hasLiDAR {
            phase = .scanning
        } else if hasPhotogrammetry {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            sampleDir          = dir
            frameCount         = 0
            processingProgress = 0
            phase              = .capturing
        } else {
            Task { await createVirtualRoom() }
        }
    }

    @available(iOS 17, *)
    private func runPhotogrammetry() async {
        guard let dir = sampleDir else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".usdz")

        do {
            var config = PhotogrammetrySession.Configuration()
            config.sampleOrdering   = .sequential
            config.featureSensitivity = .high

            let session = try PhotogrammetrySession(input: dir, configuration: config)
            let requests: [PhotogrammetrySession.Request] = [
                .modelFile(url: outputURL, detail: .reduced)
            ]
            try session.process(requests: requests)

            for try await output in session.outputs {
                switch output {
                case .processingComplete:
                    cleanupSamples()
                    await upload(fileURL: outputURL)
                    try? FileManager.default.removeItem(at: outputURL)
                case .requestProgress(_, let fraction):
                    processingProgress = fraction
                case .requestError(_, let error):
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        phase = .naming
                    }
                    cleanupSamples()
                default:
                    break
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                phase = .naming
            }
            cleanupSamples()
        }
    }

    private func cleanupSamples() {
        if let dir = sampleDir {
            try? FileManager.default.removeItem(at: dir)
            sampleDir = nil
        }
    }

    private func cleanupAndDismiss() {
        cleanupSamples()
        dismiss()
    }

    /// Non-LiDAR: placeholder USDZ so the backend has a file to store
    private func createVirtualRoom() async {
        phase = .uploading
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".usdz")
        let scene = SCNScene()
        let box = SCNBox(width: 5, height: 3, length: 5, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.clear
        scene.rootNode.addChildNode(SCNNode(geometry: box))

        guard scene.write(to: tempURL, options: nil, delegate: nil, progressHandler: nil) else {
            errorMessage = "Failed to generate placeholder."
            phase = .naming
            return
        }
        await upload(fileURL: tempURL)
    }

    private func upload(fileURL: URL) async {
        phase = .uploading
        do {
            _ = try await APIClient.shared.createRoom(
                name: roomName.trimmingCharacters(in: .whitespaces),
                fileURL: fileURL
            )
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .naming
            isProcessing    = false
            finishRequested = false
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Photogrammetry Frame Capture

struct PhotogrammetryCaptureRepresentable: UIViewRepresentable {
    let sampleDir:     URL
    let onFrameCount:  (Int) -> Void
    let onMeshUpdated: (Int) -> Void

    func makeCoordinator() -> PhotogrammetryCaptureCoordinator {
        PhotogrammetryCaptureCoordinator(sampleDir: sampleDir,
                                          onFrameCount: onFrameCount,
                                          onMeshUpdated: onMeshUpdated)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        context.coordinator.setup(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView,
                                coordinator: PhotogrammetryCaptureCoordinator) {
        uiView.session.pause()
    }
}

final class PhotogrammetryCaptureCoordinator: NSObject, ARSCNViewDelegate {
    private weak var sceneView:    ARSCNView?
    private let sampleDir:         URL
    private let onFrameCount:      (Int) -> Void
    private let onMeshUpdated:     (Int) -> Void
    private var frameCount         = 0
    private var meshNodeCount      = 0
    private var lastCapture:       TimeInterval = 0
    private let captureInterval:   TimeInterval = 1.0
    private var lastPosition:      SIMD3<Float>?
    private let minMovement:       Float = 0.03
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(sampleDir: URL,
         onFrameCount:  @escaping (Int) -> Void,
         onMeshUpdated: @escaping (Int) -> Void) {
        self.sampleDir     = sampleDir
        self.onFrameCount  = onFrameCount
        self.onMeshUpdated = onMeshUpdated
    }

    func setup(_ view: ARSCNView) {
        sceneView = view
        view.delegate = self
        view.autoenablesDefaultLighting = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Mesh wireframe (same style as MeshScanCoordinator)

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let mesh = anchor as? ARMeshAnchor else { return nil }
        meshNodeCount += 1
        let count = meshNodeCount
        DispatchQueue.main.async { self.onMeshUpdated(count) }
        return SCNNode(geometry: buildWireframe(from: mesh))
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        node.geometry = buildWireframe(from: mesh)
    }

    private func buildWireframe(from anchor: ARMeshAnchor) -> SCNGeometry {
        let g = anchor.geometry
        let vertexSrc = SCNGeometrySource(
            buffer: g.vertices.buffer, vertexFormat: g.vertices.format,
            semantic: .vertex, vertexCount: g.vertices.count,
            dataOffset: g.vertices.offset, dataStride: g.vertices.stride)
        let normalSrc = SCNGeometrySource(
            buffer: g.normals.buffer, vertexFormat: g.normals.format,
            semantic: .normal, vertexCount: g.normals.count,
            dataOffset: g.normals.offset, dataStride: g.normals.stride)
        let faceElem = SCNGeometryElement(
            buffer: g.faces.buffer, primitiveType: .triangles,
            primitiveCount: g.faces.count, bytesPerIndex: g.faces.bytesPerIndex)
        let geo = SCNGeometry(sources: [vertexSrc, normalSrc], elements: [faceElem])
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.4, green: 0.851, blue: 0.8, alpha: 0.6)
        mat.lightingModel    = .constant
        mat.fillMode         = .lines
        mat.isDoubleSided    = true
        geo.firstMaterial    = mat
        return geo
    }

    // MARK: - Frame capture

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard time - lastCapture >= captureInterval,
              let frame = sceneView?.session.currentFrame else { return }

        let t   = frame.camera.transform.columns.3
        let pos = SIMD3<Float>(t.x, t.y, t.z)
        if let last = lastPosition, simd_distance(pos, last) < minMovement { return }

        lastCapture  = time
        lastPosition = pos

        let pb    = frame.capturedImage
        let ciImg = CIImage(cvPixelBuffer: pb)
        guard let cgImg = ciContext.createCGImage(ciImg, from: ciImg.extent) else { return }

        // Pixel-rotate from landscape-right to portrait so PhotogrammetrySession
        // receives correctly-oriented images (EXIF tag alone is not enough).
        let srcW = CGFloat(cgImg.width)
        let srcH = CGFloat(cgImg.height)
        let destSize = CGSize(width: min(srcH, 1920), height: min(srcW, 1920 * srcW / srcH))
        UIGraphicsBeginImageContextWithOptions(destSize, false, 1.0)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.translateBy(x: destSize.width / 2, y: destSize.height / 2)
        ctx.rotate(by: -.pi / 2)
        let drawRect = CGRect(x: -destSize.height / 2, y: -destSize.width / 2,
                               width: destSize.height, height: destSize.width)
        UIImage(cgImage: cgImg).draw(in: drawRect)
        let rotated = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let jpeg = rotated?.jpegData(compressionQuality: 0.88) else { return }

        let filename = String(format: "%05d.jpg", frameCount)
        let fileURL  = sampleDir.appendingPathComponent(filename)
        guard (try? jpeg.write(to: fileURL)) != nil else { return }

        frameCount += 1
        let count = frameCount
        DispatchQueue.main.async { self.onFrameCount(count) }
    }
}

// MARK: - Mesh Scan UIViewRepresentable (ARKit fallback)

struct MeshScanRepresentable: UIViewRepresentable {
    @Binding var finishRequested: Bool
    let onMeshUpdated:     (Int) -> Void
    let onCoverageUpdated: (Int) -> Void
    let onProgress:        (Double) -> Void
    let onExported:        (URL) -> Void

    func makeCoordinator() -> MeshScanCoordinator {
        MeshScanCoordinator(onMeshUpdated:     onMeshUpdated,
                            onCoverageUpdated: onCoverageUpdated,
                            onProgress:        onProgress,
                            onExported:        onExported)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        context.coordinator.setup(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if finishRequested {
            context.coordinator.exportAndFinish()
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: MeshScanCoordinator) {
        uiView.session.pause()
    }
}

// MARK: - Mesh Scan Coordinator

private struct CapturedFrame {
    let image:     UIImage
    let camera:    ARCamera
    let imageSize: CGSize
}

final class MeshScanCoordinator: NSObject, ARSCNViewDelegate {
    private weak var sceneView: ARSCNView?
    private let onMeshUpdated:     (Int) -> Void
    private let onCoverageUpdated: (Int) -> Void
    private let onProgress:        (Double) -> Void
    private let onExported:        (URL) -> Void
    private var meshNodeCount = 0
    private var isExporting   = false

    // Coverage tracking — nodes colored green once well-seen by a captured frame
    private var anchorNodes:    [UUID: SCNNode] = [:]
    private var coveredAnchors: Set<UUID>       = []
    private var lastCoverageCheck: TimeInterval = 0
    private let coverageCheckInterval: TimeInterval = 0.5

    private let captureQueue    = DispatchQueue(label: "mentis.capture", qos: .utility)
    private var capturedFrames: [CapturedFrame] = []
    private var lastSampleTime: TimeInterval = 0
    private let sampleInterval: TimeInterval = 0.25
    private let maxFrames = 80
    private let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    init(onMeshUpdated:     @escaping (Int) -> Void,
         onCoverageUpdated: @escaping (Int) -> Void,
         onProgress:        @escaping (Double) -> Void,
         onExported:        @escaping (URL) -> Void) {
        self.onMeshUpdated     = onMeshUpdated
        self.onCoverageUpdated = onCoverageUpdated
        self.onProgress        = onProgress
        self.onExported        = onExported
        super.init()
    }

    func setup(_ view: ARSCNView) {
        sceneView = view
        view.delegate = self
        view.autoenablesDefaultLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection      = [.horizontal, .vertical]
        // meshWithClassification uses Apple's on-device ML to segment surfaces;
        // it typically produces denser geometry around detected object classes
        // (chairs, tables, etc.) compared to plain .mesh.
        config.sceneReconstruction = .meshWithClassification
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - ARSCNViewDelegate — frame accumulation + coverage checking

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView?.session.currentFrame else { return }

        // ── Frame capture (0.25 s) ────────────────────────────────────────────
        if time - lastSampleTime >= sampleInterval {
            lastSampleTime = time
            let pixelBuffer = frame.capturedImage
            let camera      = frame.camera
            let imgW        = CVPixelBufferGetWidth(pixelBuffer)
            let imgH        = CVPixelBufferGetHeight(pixelBuffer)
            captureQueue.async { [weak self] in
                guard let self else { return }
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
                let ciImg = CIImage(cvPixelBuffer: pixelBuffer)
                guard let cgImg = self.ciContext.createCGImage(ciImg, from: ciImg.extent) else { return }
                let newFrame = CapturedFrame(
                    image:     UIImage(cgImage: cgImg),
                    camera:    camera,
                    imageSize: CGSize(width: imgW, height: imgH)
                )
                if self.capturedFrames.count >= self.maxFrames {
                    self.capturedFrames[Int.random(in: 0..<self.maxFrames)] = newFrame
                } else {
                    self.capturedFrames.append(newFrame)
                }
            }
        }

        // ── Coverage check (0.5 s) ───────────────────────────────────────────
        // Mark mesh anchors green when ≥60 % of sampled vertices are currently
        // face-on and on-screen, signalling that this chunk has been well captured.
        if time - lastCoverageCheck >= coverageCheckInterval {
            lastCoverageCheck = time
            let camera = frame.camera
            let imgW   = Double(CVPixelBufferGetWidth(frame.capturedImage))
            let imgH   = Double(CVPixelBufferGetHeight(frame.capturedImage))
            let imgSize = CGSize(width: imgW, height: imgH)
            let col2   = camera.transform.columns.2
            let camFwd = SIMD3<Float>(col2.x, col2.y, col2.z)

            for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }) {
                guard !coveredAnchors.contains(anchor.identifier) else { continue }
                let g     = anchor.geometry
                let count = g.vertices.count
                let step  = max(1, count / 20)
                let vPtr  = g.vertices.buffer.contents().advanced(by: g.vertices.offset)
                let nPtr  = g.normals.buffer.contents().advanced(by: g.normals.offset)
                var vis = 0; var total = 0
                for i in stride(from: 0, to: count, by: step) {
                    let lv = vPtr.advanced(by: i * g.vertices.stride)
                                 .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                    let ln = nPtr.advanced(by: i * g.normals.stride)
                                 .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                    let w4 = anchor.transform * SIMD4<Float>(lv.x, lv.y, lv.z, 1)
                    let n4 = anchor.transform * SIMD4<Float>(ln.x, ln.y, ln.z, 0)
                    let world = SIMD3<Float>(w4.x, w4.y, w4.z)
                    let wNorm = normalize(SIMD3<Float>(n4.x, n4.y, n4.z))
                    total += 1
                    guard simd_dot(wNorm, camFwd) > 0.2 else { continue }
                    let pt = camera.projectPoint(world, orientation: .landscapeRight,
                                                 viewportSize: imgSize)
                    let margin: CGFloat = 60
                    if pt.x >= margin && pt.x < imgSize.width - margin &&
                       pt.y >= margin && pt.y < imgSize.height - margin { vis += 1 }
                }
                guard total > 0, Float(vis) / Float(total) >= 0.6 else { continue }
                coveredAnchors.insert(anchor.identifier)
                let id = anchor.identifier
                let covered = coveredAnchors.count
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let node = self.anchorNodes[id] {
                        node.geometry?.firstMaterial?.diffuse.contents =
                            UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.65)
                    }
                    self.onCoverageUpdated(covered)
                }
            }
        }
    }

    // MARK: - ARSCNViewDelegate — live mesh wireframe

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let mesh = anchor as? ARMeshAnchor else { return nil }
        let geo = buildLiveWireframe(from: mesh)
        let node = SCNNode(geometry: geo)
        meshNodeCount += 1
        anchorNodes[mesh.identifier] = node
        let count = meshNodeCount
        DispatchQueue.main.async { self.onMeshUpdated(count) }
        return node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        // Rebuild geometry; preserve coverage color already applied to the material
        let isCovered = coveredAnchors.contains(mesh.identifier)
        let newGeo = buildLiveWireframe(from: mesh)
        newGeo.firstMaterial?.diffuse.contents = isCovered
            ? UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.65)
            : UIColor(red: 0.4, green: 0.851, blue: 0.8, alpha: 0.6)
        DispatchQueue.main.async { node.geometry = newGeo }
    }

    // MARK: - Export

    func exportAndFinish() {
        guard !isExporting else { return }
        isExporting = true
        guard let session = sceneView?.session,
              let frame   = session.currentFrame else { isExporting = false; return }
        session.pause()

        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !anchors.isEmpty else { return }

        // Drain the capture queue to get all frames collected during the scan
        var framesCopy: [CapturedFrame] = []
        captureQueue.sync { framesCopy = capturedFrames }

        // Fall back to the current frame if the scan was too short to accumulate any
        if framesCopy.isEmpty {
            let pb   = frame.capturedImage
            let imgW = CVPixelBufferGetWidth(pb)
            let imgH = CVPixelBufferGetHeight(pb)
            let ci   = CIImage(cvPixelBuffer: pb)
            if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                framesCopy = [CapturedFrame(
                    image:     UIImage(cgImage: cg),
                    camera:    frame.camera,
                    imageSize: CGSize(width: imgW, height: imgH)
                )]
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Pre-processing: normalize frame brightness so adjacent anchor chunks
            // that use different frames don't show obvious exposure discontinuities.
            let processedFrames = self.normalizeExposure(framesCopy)

            var glbMeshes: [GLBWriter.Mesh] = []
            let total = anchors.count

            for (idx, anchor) in anchors.enumerated() {
                let meshes = self.buildGLBMeshes(from: anchor, frames: processedFrames)
                glbMeshes.append(contentsOf: meshes)
                let progress = Double(idx + 1) / Double(total)
                DispatchQueue.main.async { self.onProgress(progress) }
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".glb")

            if GLBWriter.write(meshes: glbMeshes, to: url) {
                DispatchQueue.main.async { self.onExported(url) }
            }
        }
    }

    // MARK: - Geometry builders

    private func buildLiveWireframe(from anchor: ARMeshAnchor) -> SCNGeometry {
        let g = anchor.geometry
        let vSrc = SCNGeometrySource(
            buffer: g.vertices.buffer, vertexFormat: g.vertices.format,
            semantic: .vertex, vertexCount: g.vertices.count,
            dataOffset: g.vertices.offset, dataStride: g.vertices.stride)
        let nSrc = SCNGeometrySource(
            buffer: g.normals.buffer, vertexFormat: g.normals.format,
            semantic: .normal, vertexCount: g.normals.count,
            dataOffset: g.normals.offset, dataStride: g.normals.stride)
        let fElem = SCNGeometryElement(
            buffer: g.faces.buffer, primitiveType: .triangles,
            primitiveCount: g.faces.count, bytesPerIndex: g.faces.bytesPerIndex)
        let geo = SCNGeometry(sources: [vSrc, nSrc], elements: [fElem])
        geo.firstMaterial = wireMaterial(covered: false)
        return geo
    }

    private func wireMaterial(covered: Bool) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = covered
            ? UIColor(red: 0.2, green: 0.85, blue: 0.4,   alpha: 0.65)  // green = captured
            : UIColor(red: 0.4, green: 0.851, blue: 0.8, alpha: 0.6)   // cyan  = not yet
        mat.lightingModel = .constant
        mat.fillMode      = .lines
        mat.isDoubleSided = true
        return mat
    }

    // MARK: - GLB mesh building

    /// Entry point per ARMeshAnchor.
    /// 1. Reads world-space positions/normals.
    /// 2. Pre-computes per-(frame,vertex) visibility once (avoids redundant projectPoint calls).
    /// 3. Splits faces into horizontal / vertical orientation groups.
    /// 4. For each group runs greedy coverage selection so every included face has
    ///    ALL THREE vertices on-screen in its assigned frame → no triangular cut artefacts.
    private func buildGLBMeshes(from anchor: ARMeshAnchor,
                                 frames: [CapturedFrame]) -> [GLBWriter.Mesh] {
        let g      = anchor.geometry
        let vCount = g.vertices.count
        let fCount = g.faces.count
        guard vCount > 0, fCount > 0, !frames.isEmpty else { return [] }

        let vPtr = g.vertices.buffer.contents().advanced(by: g.vertices.offset)
        let nPtr = g.normals.buffer.contents().advanced(by: g.normals.offset)
        let fPtr = g.faces.buffer.contents()

        // ── 1. Read all face indices ──────────────────────────────────────────
        var allIdx = [Int](); allIdx.reserveCapacity(fCount * 3)
        for j in 0..<(fCount * 3) {
            allIdx.append(g.faces.bytesPerIndex == 4
                ? Int(fPtr.advanced(by: j * 4).assumingMemoryBound(to: UInt32.self).pointee)
                : Int(fPtr.advanced(by: j * 2).assumingMemoryBound(to: UInt16.self).pointee))
        }

        // ── 2. World-space positions and normals ──────────────────────────────
        var wPos  = [SIMD3<Float>](repeating: .zero, count: vCount)
        var wNorm = [SIMD3<Float>](repeating: .zero, count: vCount)
        for i in 0..<vCount {
            let lv = vPtr.advanced(by: i * g.vertices.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let ln = nPtr.advanced(by: i * g.normals.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let w4 = anchor.transform * SIMD4<Float>(lv.x, lv.y, lv.z, 1)
            let n4 = anchor.transform * SIMD4<Float>(ln.x, ln.y, ln.z, 0)
            wPos[i]  = SIMD3<Float>(w4.x, w4.y, w4.z)
            wNorm[i] = normalize(SIMD3<Float>(n4.x, n4.y, n4.z))
        }

        // ── 3. Pre-compute visibility[frameIdx * vCount + vertIdx] ────────────
        // A vertex is "visible" in a frame when it faces the camera (dot > 0.15)
        // AND projects inside the image with a safe margin (avoids edge-clamping artefacts).
        let vis = precomputeVisibility(wPos: wPos, wNorm: wNorm, frames: frames)

        // ── 4. Partition faces by surface orientation ─────────────────────────
        var horizFaces = [(Int, Int, Int)]()   // |ny| > 0.6 — floors, desk-tops, object tops
        var vertFaces  = [(Int, Int, Int)]()   // everything else — walls, screens, book spines
        for f in 0..<fCount {
            let i0 = allIdx[f*3]; let i1 = allIdx[f*3+1]; let i2 = allIdx[f*3+2]
            let avgNY = abs((wNorm[i0].y + wNorm[i1].y + wNorm[i2].y) / 3.0)
            if avgNY > 0.6 { horizFaces.append((i0, i1, i2)) }
            else            { vertFaces.append((i0, i1, i2)) }
        }

        // ── 5. Greedy coverage selection for each orientation group ───────────
        var result = [GLBWriter.Mesh]()
        for faceGroup in [horizFaces, vertFaces] where !faceGroup.isEmpty {
            let meshes = buildCoverageSubsets(wPos: wPos, wNorm: wNorm,
                                              faces: faceGroup, frames: frames,
                                              vis: vis, vCount: vCount)
            result.append(contentsOf: meshes)
        }
        return result
    }

    /// Computes a flat Bool array indexed as [frameIdx * vCount + vertIdx].
    /// True = vertex is face-on to the camera AND within the image (with margin).
    private func precomputeVisibility(wPos: [SIMD3<Float>],
                                       wNorm: [SIMD3<Float>],
                                       frames: [CapturedFrame]) -> [Bool] {
        let vCount = wPos.count
        var vis = [Bool](repeating: false, count: frames.count * vCount)
        for (fi, f) in frames.enumerated() {
            let col2   = f.camera.transform.columns.2
            let camFwd = SIMD3<Float>(col2.x, col2.y, col2.z)
            let margin: CGFloat = 20
            for vi in 0..<vCount {
                guard simd_dot(wNorm[vi], camFwd) > 0.15 else { continue }
                let pt = f.camera.projectPoint(wPos[vi], orientation: .landscapeRight,
                                               viewportSize: f.imageSize)
                vis[fi * vCount + vi] =
                    pt.x >= margin && pt.x < f.imageSize.width  - margin &&
                    pt.y >= margin && pt.y < f.imageSize.height - margin
            }
        }
        return vis
    }

    /// Greedy set-cover: repeatedly pick the frame that covers the most remaining faces
    /// (face = all 3 vertices visible), build a mesh from those faces, repeat up to 4 passes.
    /// Because every face in each pass is guaranteed on-screen, UV values are never clamped
    /// → no triangular cut artefacts.
    private func buildCoverageSubsets(wPos: [SIMD3<Float>], wNorm: [SIMD3<Float>],
                                       faces: [(Int, Int, Int)],
                                       frames: [CapturedFrame],
                                       vis: [Bool], vCount: Int) -> [GLBWriter.Mesh] {
        var remaining = Array(0..<faces.count)   // indices into faces[]
        var results   = [GLBWriter.Mesh]()

        for _ in 0..<1 where !remaining.isEmpty {
            // Find the frame that makes the most remaining faces fully visible
            var bestFi = -1
            var bestCovered = [Int]()

            for (fi, _) in frames.enumerated() {
                var covered = [Int]()
                for ri in remaining {
                    let (i0, i1, i2) = faces[ri]
                    if vis[fi*vCount+i0] && vis[fi*vCount+i1] && vis[fi*vCount+i2] {
                        covered.append(ri)
                    }
                }
                if covered.count > bestCovered.count { bestCovered = covered; bestFi = fi }
            }

            guard bestFi >= 0, !bestCovered.isEmpty else { break }

            let coveredSet = Set(bestCovered)
            remaining = remaining.filter { !coveredSet.contains($0) }

            let selectedFaces = bestCovered.map { faces[$0] }
            if let mesh = buildMeshForFaces(wPos: wPos, wNorm: wNorm,
                                             faces: selectedFaces, frame: frames[bestFi]) {
                results.append(mesh)
            }
        }

        // Any faces that no captured frame could cover (never scanned from a good angle)
        // are rendered as solid gray instead of being dropped or having their UVs clamped
        // to a photo edge and stretched across the triangle.
        if !remaining.isEmpty {
            let uncoveredFaces = remaining.map { faces[$0] }
            if let grayMesh = buildGrayMesh(wPos: wPos, wNorm: wNorm, faces: uncoveredFaces) {
                results.append(grayMesh)
            }
        }

        return results
    }

    /// Builds a GLBWriter.Mesh with no texture (gray material) for faces that
    /// were never seen from a usable angle in any captured frame.
    private func buildGrayMesh(wPos: [SIMD3<Float>], wNorm: [SIMD3<Float>],
                                faces: [(Int, Int, Int)]) -> GLBWriter.Mesh? {
        var usedSet = Set<Int>()
        for (i0, i1, i2) in faces { usedSet.insert(i0); usedSet.insert(i1); usedSet.insert(i2) }
        let usedVerts = usedSet.sorted()
        guard !usedVerts.isEmpty else { return nil }
        let remap = Dictionary(uniqueKeysWithValues: usedVerts.enumerated().map { ($1, $0) })

        var posRaw  = [Float](); posRaw.reserveCapacity(usedVerts.count * 3)
        var normRaw = [Float](); normRaw.reserveCapacity(usedVerts.count * 3)
        var uvRaw   = [Float](repeating: 0, count: usedVerts.count * 2)  // dummy UVs — no texture
        var minPos  = SIMD3<Float>( Float.infinity,  Float.infinity,  Float.infinity)
        var maxPos  = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        for vi in usedVerts {
            let world = wPos[vi]; let wNrm = wNorm[vi]
            posRaw.append(contentsOf: [world.x, world.y, world.z])
            normRaw.append(contentsOf: [wNrm.x, wNrm.y, wNrm.z])
            minPos = SIMD3<Float>(Swift.min(minPos.x,world.x), Swift.min(minPos.y,world.y), Swift.min(minPos.z,world.z))
            maxPos = SIMD3<Float>(Swift.max(maxPos.x,world.x), Swift.max(maxPos.y,world.y), Swift.max(maxPos.z,world.z))
        }

        var idxRaw = [UInt32](); idxRaw.reserveCapacity(faces.count * 3)
        for (i0, i1, i2) in faces {
            idxRaw.append(UInt32(remap[i0]!)); idxRaw.append(UInt32(remap[i1]!)); idxRaw.append(UInt32(remap[i2]!))
        }

        return GLBWriter.Mesh(
            positions:   posRaw.withUnsafeBytes  { Data($0) },
            normals:     normRaw.withUnsafeBytes  { Data($0) },
            uvs:         uvRaw.withUnsafeBytes    { Data($0) },
            indices:     idxRaw.withUnsafeBytes   { Data($0) },
            vertexCount: usedVerts.count,
            indexCount:  faces.count * 3,
            texture:     nil,   // → GLBWriter uses baseColorFactor [0.55, 0.57, 0.62] gray
            minPos:      (minPos.x, minPos.y, minPos.z),
            maxPos:      (maxPos.x, maxPos.y, maxPos.z)
        )
    }

    /// Build one GLBWriter.Mesh from a pre-validated set of faces + their assigned frame.
    /// All vertices are guaranteed on-screen so UV values are written without clamping.
    private func buildMeshForFaces(wPos: [SIMD3<Float>], wNorm: [SIMD3<Float>],
                                    faces: [(Int, Int, Int)],
                                    frame: CapturedFrame) -> GLBWriter.Mesh? {
        var usedSet = Set<Int>()
        for (i0, i1, i2) in faces { usedSet.insert(i0); usedSet.insert(i1); usedSet.insert(i2) }
        let usedVerts = usedSet.sorted()
        guard !usedVerts.isEmpty else { return nil }
        let remap = Dictionary(uniqueKeysWithValues: usedVerts.enumerated().map { ($1, $0) })

        var posRaw  = [Float](); posRaw.reserveCapacity(usedVerts.count * 3)
        var normRaw = [Float](); normRaw.reserveCapacity(usedVerts.count * 3)
        var uvRaw   = [Float](); uvRaw.reserveCapacity(usedVerts.count * 2)
        var minPos  = SIMD3<Float>( Float.infinity,  Float.infinity,  Float.infinity)
        var maxPos  = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        for vi in usedVerts {
            let world = wPos[vi]; let wNrm = wNorm[vi]
            posRaw.append(contentsOf:  [world.x, world.y, world.z])
            normRaw.append(contentsOf: [wNrm.x,  wNrm.y,  wNrm.z])
            minPos = SIMD3<Float>(Swift.min(minPos.x,world.x), Swift.min(minPos.y,world.y), Swift.min(minPos.z,world.z))
            maxPos = SIMD3<Float>(Swift.max(maxPos.x,world.x), Swift.max(maxPos.y,world.y), Swift.max(maxPos.z,world.z))
            // Vertex is on-screen — no clamping needed; UV is naturally in [0,1]
            let pt = frame.camera.projectPoint(world, orientation: .landscapeRight,
                                               viewportSize: frame.imageSize)
            uvRaw.append(contentsOf: [Float(pt.x / frame.imageSize.width),
                                      Float(pt.y / frame.imageSize.height)])
        }

        var idxRaw = [UInt32](); idxRaw.reserveCapacity(faces.count * 3)
        for (i0, i1, i2) in faces {
            idxRaw.append(UInt32(remap[i0]!)); idxRaw.append(UInt32(remap[i1]!)); idxRaw.append(UInt32(remap[i2]!))
        }

        return GLBWriter.Mesh(
            positions:   posRaw.withUnsafeBytes  { Data($0) },
            normals:     normRaw.withUnsafeBytes  { Data($0) },
            uvs:         uvRaw.withUnsafeBytes    { Data($0) },
            indices:     idxRaw.withUnsafeBytes   { Data($0) },
            vertexCount: usedVerts.count,
            indexCount:  faces.count * 3,
            texture:     frame.image,
            minPos:      (minPos.x, minPos.y, minPos.z),
            maxPos:      (maxPos.x, maxPos.y, maxPos.z)
        )
    }

    // MARK: - Pre-processing: exposure normalization

    /// Adjusts the brightness of every captured frame toward the global median luminance.
    /// This reduces the visible brightness discontinuity at chunk boundaries where
    /// adjacent anchors used frames captured under different auto-exposure settings.
    private func normalizeExposure(_ frames: [CapturedFrame]) -> [CapturedFrame] {
        guard frames.count > 1 else { return frames }

        // Sample luminance for each frame
        let lums = frames.map { computeLuminance($0.image) }
        let sorted = lums.sorted()
        let median = sorted[sorted.count / 2]

        return frames.enumerated().map { (idx, frame) in
            let delta = median - lums[idx]
            // Skip correction if near-median or delta is extreme (likely wrong exposure read)
            guard abs(delta) > 0.02 && abs(delta) < 0.4 else { return frame }
            let brightness = max(-0.25, min(0.25, delta))  // clamp to safe range
            guard let adjusted = applyBrightness(frame.image, brightness: brightness)
            else { return frame }
            return CapturedFrame(image: adjusted, camera: frame.camera, imageSize: frame.imageSize)
        }
    }

    private func computeLuminance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0.5 }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return 0.5 }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        // ITU-R BT.709 luminance coefficients
        return 0.2126 * Double(px[0])/255 + 0.7152 * Double(px[1])/255 + 0.0722 * Double(px[2])/255
    }

    private func applyBrightness(_ image: UIImage, brightness: Double) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let out = filter.outputImage,
              let outCG = ciContext.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: outCG)
    }
}
