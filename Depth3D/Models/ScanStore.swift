import Foundation
import SwiftUI
import SceneKit

/// Metadata for a draft scan that was auto-saved when the app backgrounded
/// during an active scan. Lets the user recover their work.
struct DraftScanMeta: Codable {
    let vertexCount: Int
    let faceCount: Int
    let date: Date

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

final class ScanStore: ObservableObject {
    @Published var scans: [Scan] = []

    /// True when scans are stored in the iCloud ubiquity container and sync
    /// across the user's devices. Updated asynchronously after init.
    @Published var isUsingICloud: Bool = false

    private let fm = FileManager.default
    private let containerID = "iCloud.com.depth3d.scanner"
    private var cachedScansDirectory: URL?

    var scansDirectory: URL {
        if let cached = cachedScansDirectory { return cached }
        let local = localScansDirectory
        cachedScansDirectory = local
        return local
    }

    private var localScansDirectory: URL {
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
        // Start with local store so the UI is responsive immediately,
        // then asynchronously upgrade to iCloud if it's available.
        loadIndex()
        attemptICloudUpgrade()
    }

    // MARK: - iCloud setup

    private func attemptICloudUpgrade() {
        let id = containerID
        Task.detached(priority: .background) { [weak self] in
            // url(forUbiquityContainerIdentifier:) is documented as blocking.
            guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: id) else {
                return
            }
            let docsURL = ubiquityURL.appendingPathComponent("Documents", isDirectory: true)
            let scansURL = docsURL.appendingPathComponent("Scans", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: scansURL,
                withIntermediateDirectories: true
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                // If iCloud directory has its own index, use that; otherwise the
                // current local index stays in effect (no destructive migration).
                self.cachedScansDirectory = scansURL
                self.isUsingICloud = true
                self.loadIndex()
            }
        }
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

    // MARK: - Draft scans (auto-save on app background)

    /// Hidden filenames so the draft files don't leak into the scan list.
    private var draftSCNURL: URL {
        scansDirectory.appendingPathComponent("_draft.scn")
    }

    private var draftMetaURL: URL {
        scansDirectory.appendingPathComponent("_draft.json")
    }

    /// True if there's a pending draft to recover.
    var hasDraft: Bool {
        fm.fileExists(atPath: draftSCNURL.path) && fm.fileExists(atPath: draftMetaURL.path)
    }

    /// Persist a partial scan (geometry only) so the user can recover after
    /// an unexpected backgrounding/termination during a scan.
    func saveDraft(scene: SCNScene, vertexCount: Int, faceCount: Int) {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: scene,
                requiringSecureCoding: false
            )
            try data.write(to: draftSCNURL, options: .atomic)

            let meta = DraftScanMeta(vertexCount: vertexCount, faceCount: faceCount, date: Date())
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: draftMetaURL, options: .atomic)
        } catch {
            print("ScanStore.saveDraft failed: \(error)")
        }
    }

    func loadDraftMeta() -> DraftScanMeta? {
        guard let data = try? Data(contentsOf: draftMetaURL) else { return nil }
        return try? JSONDecoder().decode(DraftScanMeta.self, from: data)
    }

    /// Promote the draft into a regular saved scan and add it to the library.
    @discardableResult
    func recoverDraft(name: String) -> Scan? {
        guard let meta = loadDraftMeta(),
              fm.fileExists(atPath: draftSCNURL.path) else { return nil }

        var scan = Scan(
            name: name,
            vertexCount: meta.vertexCount,
            faceCount: meta.faceCount
        )

        let modelURL = scansDirectory.appendingPathComponent(scan.modelFilename)
        do {
            try fm.moveItem(at: draftSCNURL, to: modelURL)
            try? fm.removeItem(at: draftMetaURL)
            save(scan: scan)
            return scan
        } catch {
            print("ScanStore.recoverDraft failed: \(error)")
            return nil
        }
    }

    func discardDraft() {
        try? fm.removeItem(at: draftSCNURL)
        try? fm.removeItem(at: draftMetaURL)
    }
}
