import SwiftUI
import SceneKit

struct ModelPreviewView: View {
    let scan: Scan
    @EnvironmentObject var store: ScanStore
    @State private var showExport = false
    @State private var viewMode: ViewMode = .solid
    @State private var scene: SCNScene?

    enum ViewMode: String, CaseIterable {
        case solid     = "Solid"
        case wireframe = "Wireframe"
        case points    = "Points"

        var icon: String {
            switch self {
            case .solid:     return "cube.fill"
            case .wireframe: return "cube"
            case .points:    return "circle.dotted"
            }
        }
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
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                viewModePicker
            }
            ToolbarItem(placement: .bottomBar) {
                Text(scan.formattedVertexCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(scan: scan, scene: scene)
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
