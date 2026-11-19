// BastionApp.swift - Main app entry point

import SwiftUI

@main
struct BastionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

#Preview {
    ContentView()
}
