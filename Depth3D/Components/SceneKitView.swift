import SwiftUI
import SceneKit

/// Wraps SCNView for interactive 3D model preview.
struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    let viewMode: ModelPreviewView.ViewMode

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor.systemBackground
        scnView.showsStatistics = false

        // Initial camera framing
        scnView.pointOfView = createCamera(for: scene)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        applyViewMode(to: uiView.scene, mode: viewMode)
    }

    // MARK: - Camera

    private func createCamera(for scene: SCNScene) -> SCNNode {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 50

        let cameraNode = SCNNode()
        cameraNode.camera = camera

        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        let extent = max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z))
        let distance = max(extent * 1.5, 0.5)

        cameraNode.position = SCNVector3(
            center.x,
            center.y + distance * 0.3,
            center.z + distance
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        return cameraNode
    }

    // MARK: - View mode

    private func applyViewMode(to scene: SCNScene?, mode: ModelPreviewView.ViewMode) {
        guard let scene else { return }

        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            // Check if geometry has per-vertex colors — don't override diffuse if so
            let hasVertexColors = geometry.sources(for: .color).isEmpty == false
            for material in geometry.materials {
                switch mode {
                case .solid:
                    material.fillMode = .fill
                    if !hasVertexColors {
                        material.diffuse.contents = material.diffuse.contents ?? UIColor.systemGray3
                    }
                case .wireframe:
                    material.fillMode = .lines
                case .points:
                    material.fillMode = .lines
                }
            }
        }
    }
}
