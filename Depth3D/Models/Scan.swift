import Foundation

struct Scan: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let date: Date
    var vertexCount: Int
    var faceCount: Int
    var modelFilename: String
    var thumbnailFilename: String?

    init(name: String, vertexCount: Int = 0, faceCount: Int = 0) {
        let id = UUID()
        self.id = id
        self.name = name
        self.date = Date()
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.modelFilename = "\(id.uuidString).scn"
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
}
