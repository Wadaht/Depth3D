import ARKit
import SceneKit
import SceneKit.ModelIO
import ModelIO
import MetalKit
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case scn  = "SCN"
    case usdz = "USDZ"
    case obj  = "OBJ"
    case stl  = "STL"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .scn:  return "scn"
        case .usdz: return "usdz"
        case .obj:  return "zip"   // OBJ + MTL + textures bundle
        case .stl:  return "stl"
        }
    }

    var mimeType: String {
        switch self {
        case .scn:  return "application/octet-stream"
        case .usdz: return "model/vnd.usdz+zip"
        case .obj:  return "application/zip"
        case .stl:  return "application/sla"
        }
    }

    var description: String {
        switch self {
        case .scn:  return "SceneKit native — full fidelity, best for opening on iOS/macOS"
        case .usdz: return "Apple format — full color, viewable in Quick Look, Messages, and AR"
        case .obj:  return "OBJ + MTL bundle (.zip) — full color for Blender, Maya, Unity"
        case .stl:  return "3D printing format — geometry only, no colors"
        }
    }

    /// True if this format embeds material textures (colors) on export.
    var preservesColors: Bool {
        self == .scn || self == .usdz || self == .obj
    }
}

enum ModelExporter {

    // MARK: - Export scene to a specific format

    static func export(scene: SCNScene, format: ExportFormat, to directory: URL, filename: String) throws -> URL {
        let url = directory.appendingPathComponent("\(filename).\(format.fileExtension)")

        switch format {
        case .scn:
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: scene,
                requiringSecureCoding: false
            )
            try data.write(to: url, options: .atomic)

        case .usdz:
            let success = scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
            guard success else { throw ExportError.writeFailed }

        case .obj:
            // Custom exporter that emits OBJ + MTL + textures, bundled into a zip.
            try OBJBundleExporter.export(scene: scene, to: url)

        case .stl:
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw ExportError.noMetalDevice
            }
            let allocator = MTKMeshBufferAllocator(device: device)
            let asset = MDLAsset(scnScene: scene, bufferAllocator: allocator)
            try asset.export(to: url)
        }

        return url
    }

    // MARK: - Save scan: build colored scene, archive, capture thumbnail

    static func saveScan(
        anchors: [ARMeshAnchor],
        captures: [CameraCapture] = [],
        name: String,
        store: ScanStore
    ) async throws -> Scan {
        // Use texture baking (camera frame as material) so USDZ export
        // preserves real-world colors. Falls back to classification colors
        // if no camera captures were collected.
        let scene = MeshProcessor.buildTexturedScene(from: anchors, captures: captures)

        // Compute stats
        var totalVerts = 0, totalFaces = 0
        for a in anchors {
            totalVerts += a.geometry.vertices.count
            totalFaces += a.geometry.faces.count
        }
        let surfaceArea = MeshProcessor.surfaceArea(of: anchors)
        let classCounts = MeshProcessor.classificationCounts(of: anchors)

        var scan = Scan(
            name: name,
            vertexCount: totalVerts,
            faceCount: totalFaces,
            surfaceAreaMeters: surfaceArea,
            classificationCounts: classCounts
        )

        // Save as .scn archive (preserves vertex colors, unlike USDZ)
        let modelURL = store.scansDirectory.appendingPathComponent(scan.modelFilename)
        let data = try NSKeyedArchiver.archivedData(withRootObject: scene, requiringSecureCoding: false)
        try data.write(to: modelURL, options: .atomic)

        // Capture thumbnail (after archiving so the temporary camera node isn't persisted)
        let thumbFilename = "\(scan.id.uuidString)_thumb.png"
        let thumbURL = store.scansDirectory.appendingPathComponent(thumbFilename)
        if let image = renderThumbnail(scene: scene, size: CGSize(width: 400, height: 400)) {
            if let data = image.pngData() {
                try? data.write(to: thumbURL)
                scan.thumbnailFilename = thumbFilename
            }
        }

        return scan
    }

    // MARK: - Render a thumbnail from a scene

    private static func renderThumbnail(scene: SCNScene, size: CGSize) -> UIImage? {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = true

        // Position camera to frame the scene
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera

        // Compute bounding box and frame
        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        let extent = max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z))
        cameraNode.position = SCNVector3(center.x, center.y + extent * 0.5, center.z + extent * 1.5)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode

        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        // Clean up: remove the temporary camera node so the scene stays pristine
        cameraNode.removeFromParentNode()

        return image
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case writeFailed
        case noMetalDevice

        var errorDescription: String? {
            switch self {
            case .writeFailed:   return "Failed to write model file."
            case .noMetalDevice: return "Metal GPU not available."
            }
        }
    }
}
