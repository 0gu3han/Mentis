import ARKit
import SceneKit

/// Manages the ARSCNView session, anchor node rendering, world map persistence,
/// and mesh/plane scanning visualisation.
final class ARSceneCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {

    // MARK: - Callbacks → SwiftUI
    var onSurfaceTapped: ((simd_float3) -> Void)?
    var onAnchorNodeTapped: ((Int) -> Void)?
    var onTrackingStateChanged: ((String) -> Void)?   // human-readable status

    // MARK: - Private state
    private weak var sceneView: ARSCNView?
    private let roomId: Int
    private var mentisNodes: [Int: SCNNode] = [:]
    private var reticleNode: SCNNode?
    private let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    init(roomId: Int) {
        self.roomId = roomId
        super.init()
    }

    // MARK: - Setup / Teardown

    func setup(_ view: ARSCNView) {
        sceneView = view
        view.delegate = self
        view.session.delegate = self
        view.autoenablesDefaultLighting = true
        view.automaticallyUpdatesLighting = true

        // Feature points for all devices — gives visual scanning feedback
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints]

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        if hasLiDAR {
            config.sceneReconstruction = .mesh  // full room mesh on LiDAR
        }

        var runOptions: ARSession.RunOptions = []
        if let worldMap = loadWorldMap() {
            config.initialWorldMap = worldMap
        } else {
            runOptions = [.resetTracking, .removeExistingAnchors]
        }

        view.session.run(config, options: runOptions)

        let reticle = makeReticle()
        view.scene.rootNode.addChildNode(reticle)
        reticleNode = reticle

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    func teardown() {
        saveWorldMap()
        sceneView?.session.pause()
    }

    // MARK: - Mentis Anchor Management

    func updateAnchors(_ anchors: [Anchor]) {
        guard let scene = sceneView?.scene else { return }
        let incomingIds = Set(anchors.map(\.id))

        for (id, node) in mentisNodes where !incomingIds.contains(id) {
            node.removeFromParentNode()
            mentisNodes.removeValue(forKey: id)
        }
        for anchor in anchors where mentisNodes[anchor.id] == nil {
            let node = makeAnchorNode(anchor)
            node.position = SCNVector3(anchor.pos[0], anchor.pos[1], anchor.pos[2])
            scene.rootNode.addChildNode(node)
            mentisNodes[anchor.id] = node
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = sceneView else { return }
        let location = gesture.location(in: view)

        // Hit-test existing Mentis nodes first
        let hits = view.hitTest(location, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let idStr = n.name, let anchorId = Int(idStr) {
                    onAnchorNodeTapped?(anchorId)
                    return
                }
                node = n.parent
            }
        }

        // Raycast onto detected surface / mesh for new anchor placement
        guard let query = view.raycastQuery(from: location,
                                            allowing: .estimatedPlane,
                                            alignment: .any) else { return }
        let results = view.session.raycast(query)
        guard let hit = results.first else { return }
        let col = hit.worldTransform.columns.3
        onSurfaceTapped?(simd_float3(col.x, col.y, col.z))
    }

    // MARK: - ARSCNViewDelegate — Reticle update

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.updateReticle() }
    }

    private func updateReticle() {
        guard let view = sceneView, let reticle = reticleNode else { return }
        let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let query = view.raycastQuery(from: centre,
                                            allowing: .estimatedPlane,
                                            alignment: .any) else {
            reticle.isHidden = true
            return
        }
        if let hit = view.session.raycast(query).first {
            let col = hit.worldTransform.columns.3
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.08
            reticle.position = SCNVector3(col.x, col.y, col.z)
            reticle.isHidden = false
            SCNTransaction.commit()
        } else {
            reticle.isHidden = true
        }
    }

    // MARK: - ARSCNViewDelegate — Plane + Mesh nodes

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        if let mesh = anchor as? ARMeshAnchor {
            return makeMeshNode(for: mesh)
        }
        if let plane = anchor as? ARPlaneAnchor {
            return makePlaneNode(for: plane)
        }
        return nil
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let mesh = anchor as? ARMeshAnchor,
           let geo = node.geometry {
            // Replace geometry with updated mesh
            DispatchQueue.main.async {
                node.geometry = self.buildMeshGeometry(from: mesh)
                node.geometry?.firstMaterial = self.meshMaterial()
            }
            return
        }

        guard let plane = anchor as? ARPlaneAnchor,
              let planeNode = node.childNodes.first,
              let geo = planeNode.geometry as? SCNPlane else { return }
        DispatchQueue.main.async {
            geo.width  = CGFloat(plane.planeExtent.width)
            geo.height = CGFloat(plane.planeExtent.height)
            planeNode.simdPosition = simd_float3(plane.center.x, 0, plane.center.z)
        }
    }

    // MARK: - ARSessionDelegate — Tracking state

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let status: String
        switch frame.camera.trackingState {
        case .notAvailable:
            status = "Initialising…"
        case .limited(.initializing):
            status = "Initialising…"
        case .limited(.relocalizing):
            status = "Relocalising — move to where you were"
        case .limited(.excessiveMotion):
            status = "Slow down"
        case .limited(.insufficientFeatures):
            status = "Point at a textured surface"
        case .normal:
            status = ""
        default:
            status = ""
        }
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingStateChanged?(status)
        }
    }

    // MARK: - Node Factories

    private func makeAnchorNode(_ anchor: Anchor) -> SCNNode {
        let container = SCNNode()
        container.name = "\(anchor.id)"

        // Glowing sphere pin (design primary colour)
        let sphere = SCNSphere(radius: 0.012)
        sphere.firstMaterial?.diffuse.contents  = UIColor(red: 0.4, green: 0.44, blue: 0.79, alpha: 1)  // #666fca
        sphere.firstMaterial?.emission.contents = UIColor(red: 0.4, green: 0.44, blue: 0.79, alpha: 0.4)
        sphere.firstMaterial?.lightingModel     = .physicallyBased
        let pin = SCNNode(geometry: sphere)
        pin.name = "\(anchor.id)"
        container.addChildNode(pin)

        // Floating text label
        let displayText = anchor.label.isEmpty ? "•" : anchor.label
        let text = SCNText(string: displayText, extrusionDepth: 0.001)
        text.font     = UIFont.boldSystemFont(ofSize: 1.0)
        text.flatness = 0.05
        text.firstMaterial?.diffuse.contents = UIColor(red: 0.875, green: 0.886, blue: 0.922, alpha: 1) // #dfe2eb

        let textNode = SCNNode(geometry: text)
        textNode.name  = "\(anchor.id)"
        textNode.scale = SCNVector3(0.005, 0.005, 0.005)

        let (bboxMin, bboxMax) = textNode.boundingBox
        let textWidth = (bboxMax.x - bboxMin.x) * 0.005
        textNode.position = SCNVector3(-textWidth / 2, 0.022, 0)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]
        container.addChildNode(textNode)

        // Card background
        let cardWidth = CGFloat(textWidth + 0.012)
        let card = SCNPlane(width: Swift.max(cardWidth, 0.04), height: 0.022)
        card.cornerRadius = 0.004
        card.firstMaterial?.diffuse.contents  = UIColor(red: 0.4, green: 0.44, blue: 0.79, alpha: 0.75)
        card.firstMaterial?.isDoubleSided     = true
        let cardNode = SCNNode(geometry: card)
        cardNode.name = "\(anchor.id)"
        cardNode.position = SCNVector3(0, 0.022, -0.001)
        let cb = SCNBillboardConstraint(); cb.freeAxes = .all
        cardNode.constraints = [cb]
        container.addChildNode(cardNode)

        return container
    }

    private func makeReticle() -> SCNNode {
        let torus = SCNTorus(ringRadius: 0.04, pipeRadius: 0.003)
        torus.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        let node = SCNNode(geometry: torus)
        node.isHidden = true
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private func makePlaneNode(for plane: ARPlaneAnchor) -> SCNNode {
        let container = SCNNode()
        let geo = SCNPlane(
            width:  CGFloat(plane.planeExtent.width),
            height: CGFloat(plane.planeExtent.height)
        )
        geo.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.44, blue: 0.79, alpha: 0.1)
        geo.firstMaterial?.isDoubleSided    = true
        let planeNode = SCNNode(geometry: geo)
        planeNode.eulerAngles.x = -.pi / 2
        planeNode.simdPosition  = simd_float3(plane.center.x, 0, plane.center.z)
        container.addChildNode(planeNode)
        return container
    }

    // MARK: - LiDAR Mesh Rendering

    private func makeMeshNode(for anchor: ARMeshAnchor) -> SCNNode {
        let node = SCNNode()
        node.geometry = buildMeshGeometry(from: anchor)
        node.geometry?.firstMaterial = meshMaterial()
        return node
    }

    private func buildMeshGeometry(from anchor: ARMeshAnchor) -> SCNGeometry {
        let g = anchor.geometry

        let vertexSource = SCNGeometrySource(
            buffer: g.vertices.buffer,
            vertexFormat: g.vertices.format,
            semantic: .vertex,
            vertexCount: g.vertices.count,
            dataOffset: g.vertices.offset,
            dataStride: g.vertices.stride
        )
        let normalSource = SCNGeometrySource(
            buffer: g.normals.buffer,
            vertexFormat: g.normals.format,
            semantic: .normal,
            vertexCount: g.normals.count,
            dataOffset: g.normals.offset,
            dataStride: g.normals.stride
        )
        let faceElement = SCNGeometryElement(
            buffer: g.faces.buffer,
            primitiveType: .triangles,
            primitiveCount: g.faces.count,
            bytesPerIndex: g.faces.bytesPerIndex
        )

        return SCNGeometry(sources: [vertexSource, normalSource], elements: [faceElement])
    }

    private func meshMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        // Teal wireframe — matches design system secondary_fixed_dim (#66d9cc)
        mat.diffuse.contents  = UIColor(red: 0.4, green: 0.851, blue: 0.8, alpha: 0.25)
        mat.isDoubleSided     = true
        mat.lightingModel     = .constant
        mat.fillMode          = .lines
        return mat
    }

    // MARK: - World Map Persistence

    func saveWorldMap() {
        sceneView?.session.getCurrentWorldMap { [weak self] worldMap, _ in
            guard let self, let map = worldMap else { return }
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: map, requiringSecureCoding: true) else { return }
            try? data.write(to: self.worldMapURL)
        }
    }

    private func loadWorldMap() -> ARWorldMap? {
        guard let data = try? Data(contentsOf: worldMapURL),
              let map  = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARWorldMap.self, from: data) else { return nil }
        return map
    }

    private var worldMapURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mentis_worldmap_\(roomId).arworldmap")
    }
}
