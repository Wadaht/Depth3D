import ARKit
import SceneKit
import ModelIO
import MetalKit

enum MeshProcessor {

    // MARK: - Convert single ARMeshAnchor → SCNGeometry

    static func geometry(from anchor: ARMeshAnchor, color: UIColor = .white) -> SCNGeometry {
        let g = anchor.geometry

        // Vertices
        let vertexSource = SCNGeometrySource(
            buffer: g.vertices.buffer,
            vertexFormat: g.vertices.format,
            semantic: .vertex,
            vertexCount: g.vertices.count,
            dataOffset: g.vertices.offset,
            dataStride: g.vertices.stride
        )

        // Normals
        let normalSource = SCNGeometrySource(
            buffer: g.normals.buffer,
            vertexFormat: g.normals.format,
            semantic: .normal,
            vertexCount: g.normals.count,
            dataOffset: g.normals.offset,
            dataStride: g.normals.stride
        )

        // Faces
        let faceBuf = g.faces.buffer
        let faceData = Data(
            bytesNoCopy: faceBuf.contents(),
            count: g.faces.count * g.faces.indexCountPerPrimitive * g.faces.bytesPerIndex,
            deallocator: .none
        )
        let element = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: g.faces.count,
            bytesPerIndex: g.faces.bytesPerIndex
        )

        let scnGeom = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        scnGeom.materials = [material]

        return scnGeom
    }

    // MARK: - Wireframe variant for live scanning overlay

    static func wireframeGeometry(from anchor: ARMeshAnchor) -> SCNGeometry {
        let geom = geometry(from: anchor, color: UIColor.cyan)
        geom.materials.first?.fillMode = .lines
        geom.materials.first?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.5)
        return geom
    }

    // MARK: - Combine all anchors into one SCNScene (world-space)

    static func buildScene(from anchors: [ARMeshAnchor]) -> SCNScene {
        let scene = SCNScene()

        for anchor in anchors {
            let color = classificationColor(for: anchor)
            let geom = geometry(from: anchor, color: color)
            let node = SCNNode(geometry: geom)
            node.simdTransform = anchor.transform
            scene.rootNode.addChildNode(node)
        }

        // Add ambient light so the model is visible in preview
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 800
        directional.light?.color = UIColor.white
        directional.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directional)

        return scene
    }

    // MARK: - Per-anchor color by dominant classification

    private static func classificationColor(for anchor: ARMeshAnchor) -> UIColor {
        guard let classification = anchor.geometry.classification else {
            return UIColor.systemGray
        }

        // Sample the first face's classification to pick a dominant color
        let ptr = classification.buffer.contents()
            .advanced(by: classification.offset)
            .bindMemory(to: UInt8.self, capacity: classification.count)

        // Count occurrences
        var counts = [UInt8: Int]()
        for i in 0..<min(classification.count, 200) {
            counts[ptr[i], default: 0] += 1
        }
        let dominant = counts.max(by: { $0.value < $1.value })?.key ?? 0

        switch ARMeshClassification(rawValue: Int(dominant)) {
        case .wall:     return UIColor(red: 0.85, green: 0.85, blue: 0.80, alpha: 1)
        case .floor:    return UIColor(red: 0.65, green: 0.60, blue: 0.55, alpha: 1)
        case .ceiling:  return UIColor(red: 0.92, green: 0.92, blue: 0.95, alpha: 1)
        case .table:    return UIColor(red: 0.70, green: 0.55, blue: 0.40, alpha: 1)
        case .seat:     return UIColor(red: 0.45, green: 0.55, blue: 0.70, alpha: 1)
        case .window:   return UIColor(red: 0.70, green: 0.85, blue: 0.95, alpha: 1)
        case .door:     return UIColor(red: 0.60, green: 0.45, blue: 0.35, alpha: 1)
        default:        return UIColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1)
        }
    }

    // MARK: - Compute bounding box of all anchors

    static func boundingBox(of anchors: [ARMeshAnchor]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for anchor in anchors {
            let g = anchor.geometry
            let ptr = g.vertices.buffer.contents()
                .advanced(by: g.vertices.offset)
                .bindMemory(to: SIMD3<Float>.self, capacity: g.vertices.count)

            for i in 0..<g.vertices.count {
                let local = ptr[i]
                let world = anchor.transform * SIMD4<Float>(local, 1)
                let p = SIMD3<Float>(world.x, world.y, world.z)
                lo = min(lo, p)
                hi = max(hi, p)
            }
        }
        return (lo, hi)
    }
}
