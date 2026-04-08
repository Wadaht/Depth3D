import ARKit
import CoreImage

/// Snapshot of a camera frame captured during scanning, used for vertex coloring.
struct CameraCapture {
    let image: CGImage
    let intrinsics: simd_float3x3
    let viewMatrix: simd_float4x4   // inverse of camera transform
    let imageWidth: Int
    let imageHeight: Int
}

/// Fast RGBA pixel sampler backed by a bitmap buffer.
final class BitmapSampler {
    let width: Int
    let height: Int
    private let pixels: [UInt8]
    private let bytesPerRow: Int

    init?(image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let ptr = context.data else { return nil }
        pixels = Array(UnsafeBufferPointer(
            start: ptr.bindMemory(to: UInt8.self, capacity: bytesPerRow * height),
            count: bytesPerRow * height
        ))
    }

    /// Sample RGB at pixel coordinates. Returns nil if out of bounds.
    func sample(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = y * bytesPerRow + x * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }
}

/// Manages camera frame capture and vertex color projection.
enum CameraColorSampler {

    private static let ciContext = CIContext()

    /// Downsample a CVPixelBuffer to a CGImage at reduced resolution.
    static func downsample(_ pixelBuffer: CVPixelBuffer, scale: CGFloat = 0.5) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    /// Project a world-space point into a capture's image and return pixel coordinates.
    /// Returns nil if the point is behind the camera or outside the image.
    static func project(
        worldPoint: SIMD3<Float>,
        capture: CameraCapture
    ) -> (x: Int, y: Int, depth: Float)? {
        // Transform to camera space
        let camPoint = capture.viewMatrix * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)

        // ARKit camera looks along -Z, so visible points have negative Z.
        // Depth is the positive distance in front of the camera.
        let depth = -camPoint.z
        guard depth > 0.05 else { return nil }

        // Project using intrinsics (column-major: [col][row])
        // u maps from camera X (right) to pixel column
        // v maps from camera -Y (up→down) to pixel row
        let fx = capture.intrinsics[0][0]
        let fy = capture.intrinsics[1][1]
        let cx = capture.intrinsics[2][0]
        let cy = capture.intrinsics[2][1]

        let u = fx * camPoint.x / depth + cx
        let v = fy * (-camPoint.y) / depth + cy

        let px = Int(u)
        let py = Int(v)

        guard px >= 0, px < capture.imageWidth, py >= 0, py < capture.imageHeight else {
            return nil
        }

        return (px, py, depth)
    }

    /// For a world-space vertex, find the best color across all captures.
    /// Prefers captures where the vertex is closer to image center and nearer to camera.
    static func sampleColor(
        worldPoint: SIMD3<Float>,
        captures: [CameraCapture],
        samplers: [BitmapSampler]
    ) -> (r: UInt8, g: UInt8, b: UInt8) {
        var bestColor: (r: UInt8, g: UInt8, b: UInt8) = (180, 180, 180)
        var bestScore: Float = .greatestFiniteMagnitude

        for (i, capture) in captures.enumerated() {
            guard let proj = project(worldPoint: worldPoint, capture: capture) else { continue }
            guard let color = samplers[i].sample(x: proj.x, y: proj.y) else { continue }

            // Score: prefer closer + more central projections
            let centerX = Float(capture.imageWidth) / 2
            let centerY = Float(capture.imageHeight) / 2
            let dx = (Float(proj.x) - centerX) / centerX
            let dy = (Float(proj.y) - centerY) / centerY
            let centrality = dx * dx + dy * dy  // 0 = center, higher = edge
            let score = proj.depth * (1.0 + centrality * 0.5)

            if score < bestScore {
                bestScore = score
                bestColor = color
            }
        }

        return bestColor
    }
}
