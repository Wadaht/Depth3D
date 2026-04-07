import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: ScanStore
    @Binding var showScanner: Bool

    var body: some View {
        Group {
            if store.scans.isEmpty {
                emptyState
            } else {
                scanList
            }
        }
        .navigationTitle("My Scans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showScanner = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
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
            ForEach(store.scans) { scan in
                NavigationLink(value: scan) {
                    ScanCard(scan: scan)
                }
            }
            .onDelete { offsets in
                for i in offsets { store.delete(scan: store.scans[i]) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Scan.self) { scan in
            ModelPreviewView(scan: scan)
        }
    }
}
