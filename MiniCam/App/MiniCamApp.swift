import SwiftUI

@main
struct MiniCamApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}

