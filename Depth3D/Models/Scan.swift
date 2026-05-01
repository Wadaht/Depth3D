import Foundation

struct Scan: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let date: Date
    var vertexCount: Int
    var faceCount: Int
    var modelFilename: String
    var thumbnailFilename: String?

    /// Total surface area of the captured mesh, in square meters.
    var surfaceAreaMeters: Double = 0

    /// Per-classification face counts (key is classification name).
    var classificationCounts: [String: Int] = [:]

    init(
        name: String,
        vertexCount: Int = 0,
        faceCount: Int = 0,
        surfaceAreaMeters: Double = 0,
        classificationCounts: [String: Int] = [:]
    ) {
        let id = UUID()
        self.id = id
        self.name = name
        self.date = Date()
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.modelFilename = "\(id.uuidString).scn"
        self.surfaceAreaMeters = surfaceAreaMeters
        self.classificationCounts = classificationCounts
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var formattedVertexCount: String {
        if vertexCount >= 1_000_000 {
            return String(format: "%.1fM vertices", Double(vertexCount) / 1_000_000)
        } else if vertexCount >= 1_000 {
            return String(format: "%.1fK vertices", Double(vertexCount) / 1_000)
        }
        return "\(vertexCount) vertices"
    }

    var formattedSurfaceArea: String {
        if surfaceAreaMeters >= 1 {
            return String(format: "%.1f m²", surfaceAreaMeters)
        } else {
            return String(format: "%.0f cm²", surfaceAreaMeters * 10_000)
        }
    }

    // MARK: - Identity-based Hashable
    // NavigationStack uses Hashable for tracking; basing hash on id keeps
    // navigation stable when a scan is renamed.

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Scan, rhs: Scan) -> Bool {
        lhs.id == rhs.id
    }
}
