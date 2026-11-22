import SwiftUI

@main
struct SKOverlayPrefetchDemoApp: App {
    @StateObject private var demo = PrefetchDemo()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(demo)
        }
    }
}
