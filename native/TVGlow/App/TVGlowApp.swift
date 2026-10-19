import SwiftUI

@main
@MainActor
struct TVGlowApp: App {
    @StateObject private var store = ControlStore()
    @StateObject private var remote = AppleRemoteStore()

    var body: some Scene {
        #if os(macOS)
        Window("TV Glow", id: "main") {
            ContentView(store: store, remote: remote).frame(minWidth: 1020, idealWidth: 1100, maxWidth: 1240, minHeight: 610, idealHeight: 730)
        }
        .defaultSize(width: 1100, height: 730)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reconnect TV") { Task { await store.connectTV() } }.keyboardShortcut("r", modifiers: [.command])
                Button("Refresh devices") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuControlsView(store: store, remote: remote)
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView(store: store, remote: remote)
        }
        #endif
    }
}
