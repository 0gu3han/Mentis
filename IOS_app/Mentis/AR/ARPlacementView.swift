import SwiftUI
import ARKit
import SceneKit

/// Pure UIViewRepresentable bridge — no UI chrome.
/// The coordinator owns all AR logic.
struct ARPlacementView: UIViewRepresentable {
    let roomId: Int
    var anchors: [Anchor]
    var onSurfaceTapped: (simd_float3) -> Void
    var onAnchorTapped: (Int) -> Void
    var onTrackingStatus: (String) -> Void

    func makeCoordinator() -> ARSceneCoordinator {
        ARSceneCoordinator(roomId: roomId)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.showsStatistics = false
        context.coordinator.onSurfaceTapped       = onSurfaceTapped
        context.coordinator.onAnchorNodeTapped    = onAnchorTapped
        context.coordinator.onTrackingStateChanged = onTrackingStatus
        context.coordinator.setup(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Called whenever SwiftUI state changes — push updated anchors to coordinator
        context.coordinator.updateAnchors(anchors)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARSceneCoordinator) {
        coordinator.teardown()
    }
}
