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

        // Create both cameras and store in coordinator
        let (perspCam, airplaneCam) = createCameras(for: scene)
        context.coordinator.perspectiveCamera = perspCam
        context.coordinator.airplaneCamera = airplaneCam
        scene.rootNode.addChildNode(perspCam)
        scene.rootNode.addChildNode(airplaneCam)

        scnView.pointOfView = perspCam
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        applyViewMode(to: uiView, mode: viewMode, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var perspectiveCamera: SCNNode?
        var airplaneCamera: SCNNode?
        var currentMode: ModelPreviewView.ViewMode = .solid
    }

    // MARK: - Cameras

    private func createCameras(for scene: SCNScene) -> (SCNNode, SCNNode) {
        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        let extentX = maxB.x - minB.x
        let extentY = maxB.y - minB.y
        let extentZ = maxB.z - minB.z
        let extent = max(extentX, max(extentY, extentZ))
        let distance = max(extent * 1.5, 0.5)

        // Perspective camera (default orbit view)
        let perspCamera = SCNCamera()
        perspCamera.automaticallyAdjustsZRange = true
        perspCamera.fieldOfView = 50

        let perspNode = SCNNode()
        perspNode.name = "perspectiveCamera"
        perspNode.camera = perspCamera
        perspNode.position = SCNVector3(
            center.x,
            center.y + distance * 0.3,
            center.z + distance
        )
        perspNode.look(at: center)

        // Airplane camera (top-down orthographic)
        let airCamera = SCNCamera()
        airCamera.automaticallyAdjustsZRange = true
        airCamera.usesOrthographicProjection = true
        airCamera.orthographicScale = Double(max(extentX, extentZ) * 0.7)

        let airNode = SCNNode()
        airNode.name = "airplaneCamera"
        airNode.camera = airCamera
        airNode.position = SCNVector3(
            center.x,
            center.y + distance * 2,
            center.z
        )
        airNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)  // Look straight down

        return (perspNode, airNode)
    }

    // MARK: - View mode

    private func applyViewMode(to scnView: SCNView, mode: ModelPreviewView.ViewMode, coordinator: Coordinator) {
        guard let scene = scnView.scene else { return }

        // Switch camera for airplane mode
        let isAirplane = mode == .airplane
        let wasAirplane = coordinator.currentMode == .airplane
        coordinator.currentMode = mode

        if isAirplane && !wasAirplane {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            scnView.pointOfView = coordinator.airplaneCamera
            SCNTransaction.commit()
        } else if !isAirplane && wasAirplane {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            scnView.pointOfView = coordinator.perspectiveCamera
            SCNTransaction.commit()
        }

        // Apply fill mode to materials
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            let hasVertexColors = geometry.sources(for: .color).isEmpty == false
            for material in geometry.materials {
                switch mode {
                case .solid, .airplane:
                    material.fillMode = .fill
                    if !hasVertexColors {
                        material.diffuse.contents = material.diffuse.contents ?? UIColor.systemGray3
                    }
                case .wireframe:
                    material.fillMode = .lines
                }
            }
        }
    }
}
