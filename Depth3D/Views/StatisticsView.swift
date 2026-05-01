import SwiftUI

struct StatisticsView: View {
    let scan: Scan
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                if !scan.classificationCounts.isEmpty {
                    classificationsSection
                }
                fileSection
            }
            .navigationTitle("Scan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section("Overview") {
            statRow("Captured", scan.formattedDate)
            statRow("Vertices", scan.vertexCount.formatted())
            statRow("Triangles", scan.faceCount.formatted())
            statRow("Surface Area", scan.formattedSurfaceArea)
        }
    }

    // MARK: - Classifications

    private var classificationsSection: some View {
        let total = scan.classificationCounts.values.reduce(0, +)
        let sorted = scan.classificationCounts.sorted { $0.value > $1.value }

        return Section("Surfaces") {
            ForEach(sorted, id: \.key) { key, count in
                ClassificationRow(
                    name: MeshProcessor.classificationDisplayName(key),
                    count: count,
                    total: total
                )
            }
        }
    }

    // MARK: - File

    private var fileSection: some View {
        Section("File") {
            statRow("Format", "SceneKit (.scn)")
            statRow("Size", fileSize)
        }
    }

    // MARK: - Helpers

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var fileSize: String {
        let url = store.modelURL(for: scan)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Classification row with progress bar

private struct ClassificationRow: View {
    let name: String
    let count: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    private var color: Color {
        switch name.lowercased() {
        case "wall":    return .gray
        case "floor":   return .brown
        case "ceiling": return .white
        case "table":   return .orange
        case "seat":    return .blue
        case "window":  return .cyan
        case "door":    return Color(red: 0.6, green: 0.4, blue: 0.2)
        default:        return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                Spacer()
                Text(percentString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }

    private var percentString: String {
        String(format: "%.1f%%", fraction * 100)
    }
}
