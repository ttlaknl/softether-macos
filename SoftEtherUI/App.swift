// App.swift
// SwiftUI Application Entry for macOS and iOS (arm64 Apple Silicon)

import SwiftUI

@main
struct SoftEtherUIApp: App {
    @StateObject private var engine = SoftEtherEngine.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(engine)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            SidebarCommands()
        }
        #endif
    }
}
