import Foundation
import SceneKit
import UIKit

/// Custom OBJ + MTL exporter that preserves textures.
///
/// `MDLAsset.export(to:)` writes only geometry to .obj — colors and textures
/// are dropped. This exporter walks the scene, writes a Wavefront OBJ with
/// per-node groups, a companion MTL with `map_Kd` references, and PNG files
/// for each unique texture. The whole bundle is zipped into a single file
/// using NSFileCoordinator's upload semantics.
enum OBJBundleExporter {

    /// Build the bundle and write it to `zipURL` (which should end in `.zip`).
    static func export(scene: SCNScene, to zipURL: URL) throws {
        let baseName = zipURL.deletingPathExtension().lastPathComponent

        // Stage all files inside a uniquely-named temp folder. Whatever's in
        // the inner `baseName/` becomes the contents of the zip.
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workDir = tempBase.appendingPathComponent(baseName, isDirectory: true)

        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        try writeBundle(scene: scene, to: workDir, baseName: baseName)
        try zipDirectory(at: workDir, to: zipURL)
    }

    // MARK: - Bundle writer

    private static func writeBundle(scene: SCNScene, to dir: URL, baseName: String) throws {
        var obj: [String] = [
            "# Depth3D OBJ export",
            "# https://depth3d.app",
            "mtllib \(baseName).mtl"
        ]
        var mtl: [String] = ["# Depth3D MTL"]

        // Track texture instances we've already written, keyed by image identity
        var textureFiles: [ObjectIdentifier: String] = [:]

        // Index offsets are 1-based and accumulate across all groups
        var vOffset = 1
        var vnOffset = 1
        var vtOffset = 1
        var groupIndex = 0

        let meshNodes = collectMeshNodes(scene.rootNode)

        for node in meshNodes {
            guard let geometry = node.geometry,
                  let element = geometry.elements.first else { continue }

            let positions = readVec3(geometry, semantic: .vertex)
            guard !positions.isEmpty else { continue }

            let normals = readVec3(geometry, semantic: .normal)
            let uvs = readVec2(geometry, semantic: .texcoord)
            let indices = readIndices(element)
            guard !indices.isEmpty else { continue }

            let matName = "mat_\(groupIndex)"
            let worldXf = node.simdWorldTransform

            obj.append("g part_\(groupIndex)")
            obj.append("usemtl \(matName)")

            // Vertices in world space
            for p in positions {
                let w = worldXf * SIMD4<Float>(p.x, p.y, p.z, 1)
                obj.append("v \(fmt(w.x)) \(fmt(w.y)) \(fmt(w.z))")
            }

            // Normals: rotate by world transform (w=0)
            for n in normals {
                let w = worldXf * SIMD4<Float>(n.x, n.y, n.z, 0)
                obj.append("vn \(fmt(w.x)) \(fmt(w.y)) \(fmt(w.z))")
            }

            // Texcoords: pass through
            for uv in uvs {
                obj.append("vt \(fmt(uv.x)) \(fmt(uv.y))")
            }

            // Faces
            let hasUV = !uvs.isEmpty
            let hasN = !normals.isEmpty
            for f in stride(from: 0, to: indices.count - 2, by: 3) {
                let a = indices[f] + vOffset
                let b = indices[f + 1] + vOffset
                let c = indices[f + 2] + vOffset
                obj.append(faceLine(a: a, b: b, c: c,
                                    aOff: vOffset, bOff: vOffset, cOff: vOffset,
                                    vtOff: vtOffset, vnOff: vnOffset,
                                    hasUV: hasUV, hasN: hasN,
                                    rawA: indices[f], rawB: indices[f + 1], rawC: indices[f + 2]))
            }

            // Material entry
            try writeMaterial(
                geometry.materials.first,
                name: matName,
                in: dir,
                baseName: baseName,
                groupIndex: groupIndex,
                textureCache: &textureFiles,
                lines: &mtl
            )

            vOffset += positions.count
            vnOffset += normals.count
            vtOffset += uvs.count
            groupIndex += 1
        }

        try obj.joined(separator: "\n").write(
            to: dir.appendingPathComponent("\(baseName).obj"),
            atomically: true,
            encoding: .utf8
        )
        try mtl.joined(separator: "\n").write(
            to: dir.appendingPathComponent("\(baseName).mtl"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Material writer

    private static func writeMaterial(
        _ material: SCNMaterial?,
        name: String,
        in dir: URL,
        baseName: String,
        groupIndex: Int,
        textureCache: inout [ObjectIdentifier: String],
        lines: inout [String]
    ) throws {
        lines.append("")
        lines.append("newmtl \(name)")
        lines.append("Ka 1.000 1.000 1.000")
        lines.append("Ks 0.000 0.000 0.000")
        lines.append("Ns 10.000")
        lines.append("d 1.000")
        lines.append("illum 2")

        if let image = material?.diffuse.contents as? UIImage {
            let id = ObjectIdentifier(image)
            let texFile: String
            if let cached = textureCache[id] {
                texFile = cached
            } else {
                texFile = "\(baseName)_tex_\(textureCache.count).png"
                let texURL = dir.appendingPathComponent(texFile)
                if let data = image.pngData() {
                    try data.write(to: texURL)
                }
                textureCache[id] = texFile
            }
            lines.append("Kd 1.000 1.000 1.000")
            lines.append("map_Kd \(texFile)")
        } else if let color = material?.diffuse.contents as? UIColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            lines.append("Kd \(fmt(Float(r))) \(fmt(Float(g))) \(fmt(Float(b)))")
        } else {
            lines.append("Kd 0.700 0.700 0.700")
        }
    }

    // MARK: - Geometry readers

    private static func collectMeshNodes(_ root: SCNNode) -> [SCNNode] {
        var found: [SCNNode] = []
        root.enumerateChildNodes { node, _ in
            if node.geometry != nil {
                found.append(node)
            }
        }
        return found
    }

    private static func readVec3(_ geometry: SCNGeometry, semantic: SCNGeometrySource.Semantic) -> [SIMD3<Float>] {
        guard let source = geometry.sources(for: semantic).first,
              source.usesFloatComponents,
              source.bytesPerComponent == 4,
              source.componentsPerVector >= 3 else { return [] }

        var result = [SIMD3<Float>]()
        result.reserveCapacity(source.vectorCount)

        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<source.vectorCount {
                let p = base.advanced(by: source.dataOffset + i * source.dataStride)
                let x = p.load(fromByteOffset: 0, as: Float.self)
                let y = p.load(fromByteOffset: 4, as: Float.self)
                let z = p.load(fromByteOffset: 8, as: Float.self)
                result.append(SIMD3<Float>(x, y, z))
            }
        }
        return result
    }

    private static func readVec2(_ geometry: SCNGeometry, semantic: SCNGeometrySource.Semantic) -> [SIMD2<Float>] {
        guard let source = geometry.sources(for: semantic).first,
              source.usesFloatComponents,
              source.bytesPerComponent == 4,
              source.componentsPerVector >= 2 else { return [] }

        var result = [SIMD2<Float>]()
        result.reserveCapacity(source.vectorCount)

        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<source.vectorCount {
                let p = base.advanced(by: source.dataOffset + i * source.dataStride)
                let u = p.load(fromByteOffset: 0, as: Float.self)
                let v = p.load(fromByteOffset: 4, as: Float.self)
                result.append(SIMD2<Float>(u, v))
            }
        }
        return result
    }

    private static func readIndices(_ element: SCNGeometryElement) -> [Int] {
        let total = element.primitiveCount * 3   // we only use triangles
        let bpi = element.bytesPerIndex
        var result = [Int]()
        result.reserveCapacity(total)

        element.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<total {
                if bpi == 2 {
                    let v = base.load(fromByteOffset: i * 2, as: UInt16.self)
                    result.append(Int(v))
                } else {
                    let v = base.load(fromByteOffset: i * 4, as: UInt32.self)
                    result.append(Int(v))
                }
            }
        }
        return result
    }

    // MARK: - Face line emission

    private static func faceLine(
        a: Int, b: Int, c: Int,
        aOff: Int, bOff: Int, cOff: Int,
        vtOff: Int, vnOff: Int,
        hasUV: Bool, hasN: Bool,
        rawA: Int, rawB: Int, rawC: Int
    ) -> String {
        let aT = rawA + vtOff
        let bT = rawB + vtOff
        let cT = rawC + vtOff
        let aN = rawA + vnOff
        let bN = rawB + vnOff
        let cN = rawC + vnOff

        if hasUV && hasN {
            return "f \(a)/\(aT)/\(aN) \(b)/\(bT)/\(bN) \(c)/\(cT)/\(cN)"
        } else if hasN {
            return "f \(a)//\(aN) \(b)//\(bN) \(c)//\(cN)"
        } else if hasUV {
            return "f \(a)/\(aT) \(b)/\(bT) \(c)/\(cT)"
        } else {
            return "f \(a) \(b) \(c)"
        }
    }

    // MARK: - Zip helper

    private static func zipDirectory(at sourceURL: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: sourceURL,
                               options: [.forUploading],
                               error: &coordError) { tempZipURL in
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: tempZipURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let e = coordError { throw e }
        if let e = copyError { throw e }
    }

    // MARK: - Number formatting

    private static func fmt(_ f: Float) -> String {
        // %g chops trailing zeros, keeps reasonable precision
        String(format: "%.6g", f)
    }
}
