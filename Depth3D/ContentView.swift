import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScanStore
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            HomeView(showScanner: $showScanner)
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerContainerView()
                .environmentObject(store)
        }
    }
}
