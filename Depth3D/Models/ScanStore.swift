import Foundation
import SwiftUI

final class ScanStore: ObservableObject {
    @Published var scans: [Scan] = []

    private let fm = FileManager.default

    var scansDirectory: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Scans", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL {
        scansDirectory.appendingPathComponent("index.json")
    }

    init() {
        loadIndex()
    }

    // MARK: - CRUD

    func save(scan: Scan) {
        if let i = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[i] = scan
        } else {
            scans.insert(scan, at: 0)
        }
        persistIndex()
    }

    func delete(scan: Scan) {
        let modelURL = scansDirectory.appendingPathComponent(scan.modelFilename)
        try? fm.removeItem(at: modelURL)
        if let thumb = scan.thumbnailFilename {
            try? fm.removeItem(at: scansDirectory.appendingPathComponent(thumb))
        }
        scans.removeAll { $0.id == scan.id }
        persistIndex()
    }

    func rename(scan: Scan, to newName: String) {
        guard var s = scans.first(where: { $0.id == scan.id }) else { return }
        s.name = newName
        save(scan: s)
    }

    func modelURL(for scan: Scan) -> URL {
        scansDirectory.appendingPathComponent(scan.modelFilename)
    }

    func thumbnailURL(for scan: Scan) -> URL? {
        guard let name = scan.thumbnailFilename else { return nil }
        return scansDirectory.appendingPathComponent(name)
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Scan].self, from: data) else { return }
        scans = decoded
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
