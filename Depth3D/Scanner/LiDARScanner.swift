import ARKit
import Combine

final class LiDARScanner: NSObject, ObservableObject {
    // MARK: - Published state

    @Published var isScanning = false
    @Published var vertexCount = 0
    @Published var faceCount = 0
    @Published var meshAnchors: [ARMeshAnchor] = []
    @Published var sessionError: String?

    /// Camera frames captured during scanning for vertex coloring.
    private(set) var cameraCaptures: [CameraCapture] = []
    private var lastCaptureTime: TimeInterval = 0
    private let captureInterval: TimeInterval = 0.5
    private let maxCaptures = 50

    // MARK: - AR Session

    let session = ARSession()

    static var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Controls

    func start() {
        guard Self.isLiDARAvailable else {
            sessionError = "This device does not have a LiDAR sensor."
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning = true
        sessionError = nil
    }

    func stop() {
        session.pause()
        isScanning = false
    }

    func reset() {
        meshAnchors.removeAll()
        cameraCaptures.removeAll()
        lastCaptureTime = 0
        vertexCount = 0
        faceCount = 0
        if isScanning {
            start()
        }
    }

    // MARK: - Mesh statistics

    private func recount() {
        var verts = 0
        var faces = 0
        for anchor in meshAnchors {
            verts += anchor.geometry.vertices.count
            faces += anchor.geometry.faces.count
        }
        vertexCount = verts
        faceCount = faces
    }
}

// MARK: - ARSessionDelegate

extension LiDARScanner: ARSessionDelegate {

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        mergeMeshAnchors(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        mergeMeshAnchors(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removed = Set(anchors.map(\.identifier))
        meshAnchors.removeAll { removed.contains($0.identifier) }
        recount()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }
        let now = frame.timestamp
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now

        // Downsample and store camera frame for vertex coloring
        let pixelBuffer = frame.capturedImage
        // Scale intrinsics to match downsampled resolution
        let scale: CGFloat = 0.5
        guard let cgImage = CameraColorSampler.downsample(pixelBuffer, scale: scale) else { return }

        var intrinsics = frame.camera.intrinsics
        let s = Float(scale)
        intrinsics[0][0] *= s  // fx
        intrinsics[1][1] *= s  // fy
        intrinsics[2][0] *= s  // cx
        intrinsics[2][1] *= s  // cy

        let capture = CameraCapture(
            image: cgImage,
            intrinsics: intrinsics,
            viewMatrix: simd_inverse(frame.camera.transform),
            imageWidth: cgImage.width,
            imageHeight: cgImage.height
        )
        cameraCaptures.append(capture)

        // Evict oldest if over limit
        if cameraCaptures.count > maxCaptures {
            cameraCaptures.removeFirst()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionError = error.localizedDescription
    }

    // MARK: - Helpers

    private func mergeMeshAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            if let i = meshAnchors.firstIndex(where: { $0.identifier == mesh.identifier }) {
                meshAnchors[i] = mesh
            } else {
                meshAnchors.append(mesh)
            }
        }
        recount()
    }
}
