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

    // MARK: - Build scene with per-anchor camera-projected textures (USDZ-friendly)
    //
    // For each anchor, picks the camera capture that best frames it,
    // projects the anchor's vertices through that camera to produce UVs,
    // and uses the camera image directly as the diffuse texture.
    // Result: real-world colors that survive USDZ/AirDrop/Quick Look.

    static func buildTexturedScene(from anchors: [ARMeshAnchor], captures: [CameraCapture]) -> SCNScene {
        guard !captures.isEmpty else { return buildScene(from: anchors) }

        let scene = SCNScene()

        for anchor in anchors {
            let bestIdx = chooseBestCapture(for: anchor, in: captures)
            let geom: SCNGeometry
            if bestIdx >= 0 {
                geom = texturedGeometry(from: anchor, capture: captures[bestIdx])
            } else {
                // No suitable view for this anchor — fall back to classification color
                geom = geometry(from: anchor, color: classificationColor(for: anchor))
            }
            let node = SCNNode(geometry: geom)
            node.simdTransform = anchor.transform
            scene.rootNode.addChildNode(node)
        }

        addLights(to: scene)
        return scene
    }

    /// Pick the capture index whose camera best frames the anchor.
    /// Score = front-facing alignment / distance, with cutoffs for very close,
    /// very far, or off-axis viewpoints.
    private static func chooseBestCapture(for anchor: ARMeshAnchor, in captures: [CameraCapture]) -> Int {
        let anchorCenter = SIMD3<Float>(
            anchor.transform.columns.3.x,
            anchor.transform.columns.3.y,
            anchor.transform.columns.3.z
        )

        var bestIndex = -1
        var bestScore: Float = -.greatestFiniteMagnitude

        for i in 0..<captures.count {
            let capture = captures[i]
            // Camera world transform = inverse(viewMatrix)
            let camTransform = simd_inverse(capture.viewMatrix)
            let camPos = SIMD3<Float>(
                camTransform.columns.3.x,
                camTransform.columns.3.y,
                camTransform.columns.3.z
            )
            // ARKit camera looks down -Z in its own frame
            let camForward = SIMD3<Float>(
                -camTransform.columns.2.x,
                -camTransform.columns.2.y,
                -camTransform.columns.2.z
            )

            let toAnchor = anchorCenter - camPos
            let distance = simd_length(toAnchor)
            guard distance > 0.1, distance < 6.0 else { continue }

            let toAnchorNorm = toAnchor / distance
            let alignment = simd_dot(camForward, toAnchorNorm)
            // Anchor must be in front of camera (alignment > ~0.3 ≈ 72° cone)
            guard alignment > 0.3 else { continue }

            // Higher = better. Closer + better-aligned wins.
            let score = alignment / distance
            if score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }

        return bestIndex
    }

    /// Build geometry where UVs are produced by projecting world-space vertex
    /// positions through the chosen camera's intrinsics, and the camera image
    /// itself is the diffuse texture.
    static func texturedGeometry(from anchor: ARMeshAnchor, capture: CameraCapture) -> SCNGeometry {
        let g = anchor.geometry

        // Vertex data (copy out so it survives NSKeyedArchiver round-trips)
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

        // UVs from camera projection
        let uvs = projectVerticesToUVs(anchor: anchor, capture: capture)
        let uvData = uvs.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        let uvSource = SCNGeometrySource(
            data: uvData,
            semantic: .texcoord,
            vectorCount: uvs.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD2<Float>>.size
        )

        let scnGeom = SCNGeometry(
            sources: [vertexSource, normalSource, uvSource],
            elements: [element]
        )

        // Camera frame becomes the diffuse texture
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(cgImage: capture.image)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.isDoubleSided = true
        material.lightingModel = .phong
        scnGeom.materials = [material]

        return scnGeom
    }

    private static func projectVerticesToUVs(
        anchor: ARMeshAnchor,
        capture: CameraCapture
    ) -> [SIMD2<Float>] {
        let g = anchor.geometry
        var uvs = [SIMD2<Float>](repeating: SIMD2<Float>(0.5, 0.5), count: g.vertices.count)

        let imageW = Float(capture.imageWidth)
        let imageH = Float(capture.imageHeight)
        let vertexPtr = g.vertices.buffer.contents().advanced(by: g.vertices.offset)
        let stride = g.vertices.stride

        let fx = capture.intrinsics[0][0]
        let fy = capture.intrinsics[1][1]
        let cx = capture.intrinsics[2][0]
        let cy = capture.intrinsics[2][1]

        for i in 0..<g.vertices.count {
            let local = vertexPtr.advanced(by: i * stride).load(as: SIMD3<Float>.self)
            let world4 = anchor.transform * SIMD4<Float>(local, 1)

            // World → camera (ARKit: +Y up, -Z forward)
            let cam = capture.viewMatrix * world4
            // Pinhole projection expects +Y down, +Z forward
            let depth = -cam.z
            guard depth > 0.05 else { continue }

            let pixelX = fx * cam.x / depth + cx
            let pixelY = fy * (-cam.y) / depth + cy

            // Pixel (top-left origin) → UV. SceneKit textures use bottom-left
            // origin, so flip V.
            let u = pixelX / imageW
            let v = 1.0 - (pixelY / imageH)
            uvs[i] = SIMD2<Float>(u, v)
        }

        return uvs
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

    // MARK: - Surface area (square meters, world-space)

    static func surfaceArea(of anchors: [ARMeshAnchor]) -> Double {
        var total: Double = 0

        for anchor in anchors {
            let g = anchor.geometry
            let vertexPtr = g.vertices.buffer.contents().advanced(by: g.vertices.offset)
            let stride = g.vertices.stride

            let facePtr = g.faces.buffer.contents()
            let bytesPerIndex = g.faces.bytesPerIndex
            let indicesPerFace = g.faces.indexCountPerPrimitive

            for f in 0..<g.faces.count {
                let i0 = readIndex(at: f * indicesPerFace + 0, ptr: facePtr, bytesPerIndex: bytesPerIndex)
                let i1 = readIndex(at: f * indicesPerFace + 1, ptr: facePtr, bytesPerIndex: bytesPerIndex)
                let i2 = readIndex(at: f * indicesPerFace + 2, ptr: facePtr, bytesPerIndex: bytesPerIndex)

                let v0 = vertexPtr.advanced(by: i0 * stride).load(as: SIMD3<Float>.self)
                let v1 = vertexPtr.advanced(by: i1 * stride).load(as: SIMD3<Float>.self)
                let v2 = vertexPtr.advanced(by: i2 * stride).load(as: SIMD3<Float>.self)

                // Transform to world space
                let w0 = anchor.transform * SIMD4<Float>(v0, 1)
                let w1 = anchor.transform * SIMD4<Float>(v1, 1)
                let w2 = anchor.transform * SIMD4<Float>(v2, 1)

                let edge1 = SIMD3<Float>(w1.x - w0.x, w1.y - w0.y, w1.z - w0.z)
                let edge2 = SIMD3<Float>(w2.x - w0.x, w2.y - w0.y, w2.z - w0.z)
                let cross = simd_cross(edge1, edge2)
                total += Double(simd_length(cross)) * 0.5
            }
        }

        return total
    }

    private static func readIndex(at i: Int, ptr: UnsafeMutableRawPointer, bytesPerIndex: Int) -> Int {
        if bytesPerIndex == 2 {
            return Int(ptr.load(fromByteOffset: i * 2, as: UInt16.self))
        } else {
            return Int(ptr.load(fromByteOffset: i * 4, as: UInt32.self))
        }
    }

    // MARK: - Per-classification face counts

    static func classificationCounts(of anchors: [ARMeshAnchor]) -> [String: Int] {
        var counts: [String: Int] = [:]

        for anchor in anchors {
            guard let classification = anchor.geometry.classification else { continue }
            let ptr = classification.buffer.contents()
                .advanced(by: classification.offset)
                .bindMemory(to: UInt8.self, capacity: classification.count)

            for i in 0..<classification.count {
                let raw = Int(ptr[i])
                let key = classificationName(rawValue: raw)
                counts[key, default: 0] += 1
            }
        }

        return counts
    }

    static func classificationName(rawValue: Int) -> String {
        switch ARMeshClassification(rawValue: rawValue) {
        case .wall:    return "wall"
        case .floor:   return "floor"
        case .ceiling: return "ceiling"
        case .table:   return "table"
        case .seat:    return "seat"
        case .window:  return "window"
        case .door:    return "door"
        default:       return "other"
        }
    }

    static func classificationDisplayName(_ key: String) -> String {
        key.prefix(1).uppercased() + key.dropFirst()
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
