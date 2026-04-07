import SwiftUI

struct ScannerContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: ScanStore
    @StateObject private var scanner = LiDARScanner()

    @State private var showSaveDialog = false
    @State private var scanName = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
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
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
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
        let name = scanName.isEmpty ? "Scan \(store.scans.count + 1)" : scanName
        isSaving = true
        scanner.stop()

        Task {
            do {
                let scan = try await ModelExporter.saveScan(
                    anchors: scanner.meshAnchors,
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
}
