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
        Coordinator(scanner: scanner)
    }

    // MARK: - Coordinator handles mesh visualization + camera capture

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let scanner: LiDARScanner
        private var lastCaptureTime: TimeInterval = 0
        private let captureInterval: TimeInterval = 0.3
        private let downsampleScale: CGFloat = 0.25

        init(scanner: LiDARScanner) {
            self.scanner = scanner
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
            let node = SCNNode(geometry: MeshProcessor.wireframeGeometry(from: meshAnchor))
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshProcessor.wireframeGeometry(from: meshAnchor)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard scanner.isScanning else { return }
            guard time - lastCaptureTime >= captureInterval else { return }
            lastCaptureTime = time

            guard let scnView = renderer as? ARSCNView,
                  let frame = scnView.session.currentFrame else { return }

            let pixelBuffer = frame.capturedImage
            guard let cgImage = CameraColorSampler.downsample(pixelBuffer, scale: downsampleScale) else { return }

            var intrinsics = frame.camera.intrinsics
            let s = Float(downsampleScale)
            intrinsics[0][0] *= s
            intrinsics[1][1] *= s
            intrinsics[2][0] *= s
            intrinsics[2][1] *= s

            let capture = CameraCapture(
                image: cgImage,
                intrinsics: intrinsics,
                viewMatrix: simd_inverse(frame.camera.transform),
                imageWidth: cgImage.width,
                imageHeight: cgImage.height
            )
            scanner.addCapture(capture)
        }
    }
}
