import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: ScanStore
    @Binding var showScanner: Bool
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var showRecoverDraft = false
    @State private var draftMeta: DraftScanMeta?

    private var filteredScans: [Scan] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.scans }
        return store.scans.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if store.scans.isEmpty {
                emptyState
            } else if filteredScans.isEmpty {
                noResultsState
            } else {
                scanList
            }
        }
        .navigationTitle("My Scans")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search scans"
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showScanner = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { checkForDraft() }
        .alert("Recover Unsaved Scan?", isPresented: $showRecoverDraft) {
            Button("Recover") {
                if let meta = draftMeta {
                    let name = "Recovered \(meta.formattedDate)"
                    _ = store.recoverDraft(name: name)
                }
                draftMeta = nil
            }
            Button("Discard", role: .destructive) {
                store.discardDraft()
                draftMeta = nil
            }
        } message: {
            if let meta = draftMeta {
                Text("\(meta.formattedVertexCount) captured \(meta.formattedDate). Recover it as a new scan?")
            }
        }
    }

    private func checkForDraft() {
        guard store.hasDraft, let meta = store.loadDraftMeta() else { return }
        draftMeta = meta
        showRecoverDraft = true
    }

    // MARK: - No-results state

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No matches for \"\(searchText)\"")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Scans Yet")
                .font(.title2.bold())
            Text("Use your iPhone's LiDAR sensor\nto capture the world in 3D")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                showScanner = true
            } label: {
                Label("Start Scanning", systemImage: "viewfinder")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }

    // MARK: - Scan list

    private var scanList: some View {
        List {
            ForEach(filteredScans) { scan in
                NavigationLink(value: scan) {
                    ScanCard(scan: scan)
                }
            }
            .onDelete { offsets in
                for i in offsets { store.delete(scan: filteredScans[i]) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Scan.self) { scan in
            ModelPreviewView(scan: scan)
        }
    }
}
