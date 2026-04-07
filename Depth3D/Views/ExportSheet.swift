import SwiftUI

struct ExportSheet: View {
    let scan: Scan
    let scene: SCNScene?
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button { export(as: format) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(format.rawValue)
                                        .font(.headline)
                                    Text(format.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isExporting || scene == nil)
                    }
                } header: {
                    Text("Export Format")
                } footer: {
                    Text("USDZ files can be viewed directly in iOS Files, Messages, and Safari via Quick Look.")
                }

                Section {
                    shareButton
                } header: {
                    Text("Quick Share")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Export action

    private func export(as format: ExportFormat) {
        guard let scene else { return }
        isExporting = true

        Task {
            do {
                let url = try ModelExporter.export(
                    scene: scene,
                    format: format,
                    to: store.scansDirectory,
                    filename: "\(scan.id.uuidString)_export"
                )
                await MainActor.run {
                    isExporting = false
                    shareURL = url
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Quick share (USDZ)

    private var shareButton: some View {
        Button {
            let url = store.modelURL(for: scan)
            if FileManager.default.fileExists(atPath: url.path) {
                shareURL = url
                showShareSheet = true
            }
        } label: {
            Label("Share USDZ via AirDrop, Messages...", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - UIKit Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
