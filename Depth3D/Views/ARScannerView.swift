import SwiftUI
import ARKit
import SceneKit

/// UIViewRepresentable wrapping ARSCNView for live LiDAR scanning.
struct ARScannerView: UIViewRepresentable {
    @ObservedObject var scanner: LiDARScanner

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.session = scanner.session
        arView.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        arView.rendersContinuously = true
        arView.antialiasingMode = .multisampling4X

        // Show feature points for visual feedback
        arView.debugOptions = [.showFeaturePoints]

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator handles mesh visualization

    final class Coordinator: NSObject, ARSCNViewDelegate {

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
            let node = SCNNode(geometry: MeshProcessor.wireframeGeometry(from: meshAnchor))
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshProcessor.wireframeGeometry(from: meshAnchor)
        }
    }
}
