import SwiftUI

@main
struct Depth3DApp: App {
    @StateObject private var scanStore = ScanStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanStore)
                .preferredColorScheme(.dark)
        }
    }
}
