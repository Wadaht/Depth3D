import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScanStore
    @State private var showScanner = false
    @AppStorage("depth3d.hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        NavigationStack {
            HomeView(showScanner: $showScanner)
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerContainerView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView()
        }
    }
}
