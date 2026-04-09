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
        context.coordinator.scnView = scnView
        scene.rootNode.addChildNode(perspCam)
        scene.rootNode.addChildNode(airplaneCam)

        scnView.pointOfView = perspCam

        // Add custom gesture recognizers for airplane mode
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        scnView.addGestureRecognizer(pinch)
        context.coordinator.pinchGesture = pinch
        pinch.isEnabled = false

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)
        context.coordinator.panGesture = pan
        pan.isEnabled = false

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        applyViewMode(to: uiView, mode: viewMode, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var perspectiveCamera: SCNNode?
        var airplaneCamera: SCNNode?
        var currentMode: ModelPreviewView.ViewMode = .solid
        weak var scnView: SCNView?
        var pinchGesture: UIPinchGestureRecognizer?
        var panGesture: UIPanGestureRecognizer?

        private var airplaneHeight: Float = 0
        private var airplaneMinHeight: Float = 0.3
        private var airplaneMaxHeight: Float = 50

        // Camera rotation angles (radians)
        private var cameraPitch: Float = -Float.pi / 2  // starts looking straight down
        private var cameraYaw: Float = 0

        func setInitialHeight(_ height: Float, extent: Float) {
            airplaneHeight = height
            airplaneMinHeight = max(extent * 0.1, 0.2)
            airplaneMaxHeight = height * 3
        }

        func resetOrientation() {
            cameraPitch = -Float.pi / 2
            cameraYaw = 0
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camNode = airplaneCamera else { return }

            if gesture.state == .changed {
                // Move along the camera's forward direction (linear, constant speed)
                let speed = Float(gesture.scale - 1.0) * 1.5
                let forward = camNode.worldFront
                camNode.position = SCNVector3(
                    camNode.position.x + forward.x * speed,
                    camNode.position.y + forward.y * speed,
                    camNode.position.z + forward.z * speed
                )
                airplaneHeight = camNode.position.y
                gesture.scale = 1.0
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let camNode = airplaneCamera,
                  let view = scnView else { return }

            if gesture.state == .changed {
                let translation = gesture.translation(in: view)
                let sensitivity: Float = 0.005

                // Swipe left/right → rotate yaw (look left/right)
                cameraYaw -= Float(translation.x) * sensitivity
                // Swipe up/down → rotate pitch (look down/up)
                cameraPitch -= Float(translation.y) * sensitivity

                // Clamp pitch: straight down (-π/2) to horizontal (0)
                cameraPitch = cameraPitch.clamped(to: -Float.pi / 2 ... Float.pi / 2)

                camNode.eulerAngles = SCNVector3(cameraPitch, cameraYaw, 0)
                gesture.setTranslation(.zero, in: view)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
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

        // Airplane camera (top-down perspective with wide FOV)
        let airCamera = SCNCamera()
        airCamera.automaticallyAdjustsZRange = true
        airCamera.fieldOfView = 60

        let airHeight = max(extent * 1.5, 1.0)
        let airNode = SCNNode()
        airNode.name = "airplaneCamera"
        airNode.camera = airCamera
        airNode.position = SCNVector3(center.x, airHeight, center.z)
        airNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)  // Look straight down

        return (perspNode, airNode)
    }

    // MARK: - View mode

    private func applyViewMode(to scnView: SCNView, mode: ModelPreviewView.ViewMode, coordinator: Coordinator) {
        guard let scene = scnView.scene else { return }

        let isAirplane = mode == .airplane
        let wasAirplane = coordinator.currentMode == .airplane
        coordinator.currentMode = mode

        if isAirplane && !wasAirplane {
            // Entering airplane mode: disable built-in controls, enable custom gestures
            scnView.allowsCameraControl = false
            coordinator.pinchGesture?.isEnabled = true
            coordinator.panGesture?.isEnabled = true

            // Initialize height tracking and reset orientation
            if let airNode = coordinator.airplaneCamera {
                let (minB, maxB) = scene.rootNode.boundingBox
                let extent = max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z))
                coordinator.setInitialHeight(airNode.position.y, extent: extent)
                coordinator.resetOrientation()
                airNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            scnView.pointOfView = coordinator.airplaneCamera
            SCNTransaction.commit()
        } else if !isAirplane && wasAirplane {
            // Leaving airplane mode: restore built-in controls
            scnView.allowsCameraControl = true
            coordinator.pinchGesture?.isEnabled = false
            coordinator.panGesture?.isEnabled = false

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

// MARK: - Float clamping

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
