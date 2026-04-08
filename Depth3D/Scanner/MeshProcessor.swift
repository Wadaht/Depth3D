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

        addLights(to: scene)
        return scene
    }

    // MARK: - Build scene with real camera colors projected onto vertices

    static func buildColoredScene(from anchors: [ARMeshAnchor], captures: [CameraCapture]) -> SCNScene {
        // If no captures available, fall back to classification coloring
        guard !captures.isEmpty else { return buildScene(from: anchors) }

        let scene = SCNScene()

        // Pre-build bitmap samplers for all captures (done once)
        let samplers = captures.compactMap { BitmapSampler(image: $0.image) }
        let validCaptures = zip(captures, samplers).map { $0 }

        // Use only captures that produced valid samplers
        let captureList = validCaptures.map(\.0)
        let samplerList = validCaptures.map(\.1)

        for anchor in anchors {
            let geom = coloredGeometry(from: anchor, captures: captureList, samplers: samplerList)
            let node = SCNNode(geometry: geom)
            node.simdTransform = anchor.transform
            scene.rootNode.addChildNode(node)
        }

        addLights(to: scene)
        return scene
    }

    // MARK: - Geometry with per-vertex color from camera projections

    static func coloredGeometry(
        from anchor: ARMeshAnchor,
        captures: [CameraCapture],
        samplers: [BitmapSampler]
    ) -> SCNGeometry {
        let g = anchor.geometry

        // Copy vertex data from Metal buffer → Data (survives NSKeyedArchiver)
        let vertexData = Data(
            bytes: g.vertices.buffer.contents().advanced(by: g.vertices.offset),
            count: g.vertices.count * g.vertices.stride
        )
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: g.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: g.vertices.stride
        )

        // Copy normal data from Metal buffer → Data
        let normalData = Data(
            bytes: g.normals.buffer.contents().advanced(by: g.normals.offset),
            count: g.normals.count * g.normals.stride
        )
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: g.normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: g.normals.stride
        )

        // Copy face data from Metal buffer → Data
        let faceData = Data(
            bytes: g.faces.buffer.contents(),
            count: g.faces.count * g.faces.indexCountPerPrimitive * g.faces.bytesPerIndex
        )
        let element = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: g.faces.count,
            bytesPerIndex: g.faces.bytesPerIndex
        )

        // Per-vertex colors from camera projection (float RGBA for compatibility)
        let vertexPtr = g.vertices.buffer.contents()
            .advanced(by: g.vertices.offset)
        let vertexStride = g.vertices.stride

        var colorFloats = [Float](repeating: 0, count: g.vertices.count * 4)

        for i in 0..<g.vertices.count {
            let localPos = vertexPtr
                .advanced(by: i * vertexStride)
                .bindMemory(to: SIMD3<Float>.self, capacity: 1)
                .pointee

            // Transform vertex to world space
            let world4 = anchor.transform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1.0)
            let worldPos = SIMD3<Float>(world4.x, world4.y, world4.z)

            let color = CameraColorSampler.sampleColor(
                worldPoint: worldPos,
                captures: captures,
                samplers: samplers
            )

            let offset = i * 4
            colorFloats[offset]     = Float(color.r) / 255.0
            colorFloats[offset + 1] = Float(color.g) / 255.0
            colorFloats[offset + 2] = Float(color.b) / 255.0
            colorFloats[offset + 3] = 1.0
        }

        let colorData = Data(
            bytes: colorFloats,
            count: colorFloats.count * MemoryLayout<Float>.size
        )
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: g.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let scnGeom = SCNGeometry(
            sources: [vertexSource, normalSource, colorSource],
            elements: [element]
        )

        let material = SCNMaterial()
        material.isDoubleSided = true
        material.lightingModel = .phong
        scnGeom.materials = [material]

        return scnGeom
    }

    private static func addLights(to scene: SCNScene) {
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
