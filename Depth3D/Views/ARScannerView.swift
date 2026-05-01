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
        private var anchorUpdateTimes: [UUID: TimeInterval] = [:]

        /// Time over which a freshly-updated anchor fades from cyan to dim gray.
        private let coverageFadeSeconds: TimeInterval = 5.0

        private var captureInterval: TimeInterval {
            ScanSettings.shared.captureIntervalMs / 1000.0
        }

        private var downsampleScale: CGFloat {
            CGFloat(ScanSettings.shared.downsampleScale)
        }

        init(scanner: LiDARScanner) {
            self.scanner = scanner
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
            anchorUpdateTimes[meshAnchor.identifier] = CACurrentMediaTime()
            return SCNNode(geometry: MeshProcessor.wireframeGeometry(from: meshAnchor))
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return }
            anchorUpdateTimes[meshAnchor.identifier] = CACurrentMediaTime()
            node.geometry = MeshProcessor.wireframeGeometry(from: meshAnchor)
        }

        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard let meshAnchor = anchor as? ARMeshAnchor else { return }
            anchorUpdateTimes.removeValue(forKey: meshAnchor.identifier)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard scanner.isScanning else { return }

            // Coverage heatmap: every frame, recolor each anchor's wireframe
            // by how recently it was updated.
            if let scnView = renderer as? ARSCNView {
                updateCoverageHeatmap(scnView: scnView, currentTime: time)
            }

            // Camera frame capture (rate-limited)
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

        // MARK: - Coverage heatmap

        private func updateCoverageHeatmap(scnView: ARSCNView, currentTime: TimeInterval) {
            guard let frame = scnView.session.currentFrame else { return }

            for anchor in frame.anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor,
                      let node = scnView.node(for: meshAnchor),
                      let material = node.geometry?.materials.first else { continue }

                let lastUpdate = anchorUpdateTimes[meshAnchor.identifier] ?? currentTime
                let age = currentTime - lastUpdate
                material.diffuse.contents = colorForAge(age)
            }
        }

        private func colorForAge(_ age: TimeInterval) -> UIColor {
            let t = CGFloat(min(1.0, max(0, age / coverageFadeSeconds)))
            // Bright cyan (just updated) → dim gray-blue (stale)
            let r: CGFloat = lerp(0.0, 0.45, t: t)
            let g: CGFloat = lerp(0.9, 0.45, t: t)
            let b: CGFloat = lerp(1.0, 0.55, t: t)
            let a: CGFloat = lerp(0.7, 0.3, t: t)
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }

        private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
            a + (b - a) * t
        }
    }
}
