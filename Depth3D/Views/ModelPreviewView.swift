import SwiftUI
import SceneKit

struct ModelPreviewView: View {
    let scan: Scan
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @State private var showExport = false
    @State private var viewMode: ViewMode = .solid
    @State private var scene: SCNScene?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showStats = false

    enum ViewMode: String, CaseIterable {
        case solid     = "Solid"
        case wireframe = "Wireframe"
        case airplane  = "Airplane"

        var icon: String {
            switch self {
            case .solid:     return "cube.fill"
            case .wireframe: return "cube"
            case .airplane:  return "airplane"
            }
        }
    }

    /// Resolve the live scan from the store so renames reflect immediately.
    private var liveScan: Scan {
        store.scans.first(where: { $0.id == scan.id }) ?? scan
    }

    var body: some View {
        ZStack {
            if let scene {
                SceneKitView(scene: scene, viewMode: viewMode)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Loading model...")
            }
        }
        .navigationTitle(liveScan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameText = liveScan.name
                        showRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { showStats = true } label: {
                        Label("Scan Details", systemImage: "info.circle")
                    }
                    Button { showExport = true } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                viewModePicker
            }
            ToolbarItem(placement: .bottomBar) {
                Text(liveScan.formattedVertexCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(scan: liveScan, scene: scene)
        }
        .sheet(isPresented: $showStats) {
            StatisticsView(scan: liveScan)
        }
        .alert("Rename Scan", isPresented: $showRename) {
            TextField("Scan name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.rename(scan: liveScan, to: trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Scan?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.delete(scan: liveScan)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(liveScan.name)\" and its 3D model file.")
        }
        .task { await loadScene() }
    }

    // MARK: - View mode picker

    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    // MARK: - Load scene from saved USDZ

    private func loadScene() async {
        let url = store.modelURL(for: scan)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded: SCNScene
            if url.pathExtension == "scn" {
                // Load .scn archive (preserves vertex colors)
                let data = try Data(contentsOf: url)
                guard let scene = try NSKeyedUnarchiver.unarchivedObject(ofClass: SCNScene.self, from: data) else {
                    print("Failed to unarchive scene")
                    return
                }
                loaded = scene
            } else {
                loaded = try SCNScene(url: url, options: [
                    .checkConsistency: true
                ])
            }
            await MainActor.run { scene = loaded }
        } catch {
            print("Failed to load scene: \(error)")
        }
    }
}
