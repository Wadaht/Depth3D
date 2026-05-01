import SwiftUI

struct ScannerContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var store: ScanStore
    @StateObject private var scanner = LiDARScanner()

    @State private var showSaveDialog = false
    @State private var scanName = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            if LiDARScanner.isLiDARAvailable {
                // AR camera + mesh overlay
                ARScannerView(scanner: scanner)
                    .ignoresSafeArea()

                // HUD overlay
                ScanOverlayView(
                    scanner: scanner,
                    onClose: { dismiss() },
                    onReset: { scanner.reset() },
                    onFinish: { showSaveDialog = true }
                )

                // Saving overlay
                if isSaving {
                    savingOverlay
                }
            } else {
                noLiDARView
            }
        }
        .onAppear {
            if LiDARScanner.isLiDARAvailable { scanner.start() }
        }
        .onDisappear { scanner.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                autoSaveDraft()
            }
        }
        .statusBarHidden()
        .alert("Save Scan", isPresented: $showSaveDialog) {
            TextField("Scan name", text: $scanName)
            Button("Save") { performSave() }
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(scanner.vertexCount.formatted()) vertices captured")
        }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Saving

    private func performSave() {
        let prefix = ScanSettings.shared.defaultNamePrefix
        let trimmed = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "\(prefix) \(store.scans.count + 1)" : trimmed
        isSaving = true
        scanner.stop()

        Task {
            do {
                let scan = try await ModelExporter.saveScan(
                    anchors: scanner.meshAnchors,
                    captures: scanner.cameraCaptures,
                    name: name,
                    store: store
                )
                await MainActor.run {
                    store.save(scan: scan)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Draft auto-save on background

    private func autoSaveDraft() {
        guard scanner.isScanning, !scanner.meshAnchors.isEmpty else { return }
        // Use geometry-only scene (fast, classification-colored) so the save
        // fits within iOS's brief background window. Recovery brings back the
        // mesh; users can re-scan if they need photographic textures.
        let scene = MeshProcessor.buildScene(from: scanner.meshAnchors)
        store.saveDraft(
            scene: scene,
            vertexCount: scanner.vertexCount,
            faceCount: scanner.faceCount
        )
    }

    // MARK: - Saving overlay

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Saving scan...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - No-LiDAR fallback

    private var noLiDARView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("LiDAR Required")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("Laseris uses your device's LiDAR sensor for accurate 3D scanning. This feature is available on:")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Label("iPhone 12 Pro and later (Pro models)", systemImage: "iphone")
                    Label("iPad Pro (2020) and later", systemImage: "ipad")
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding()
        }
    }
}
