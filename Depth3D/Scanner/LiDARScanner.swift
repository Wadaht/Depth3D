import ARKit
import Combine

final class LiDARScanner: NSObject, ObservableObject {
    // MARK: - Published state

    @Published var isScanning = false
    @Published var vertexCount = 0
    @Published var faceCount = 0
    @Published var meshAnchors: [ARMeshAnchor] = []
    @Published var sessionError: String?

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
