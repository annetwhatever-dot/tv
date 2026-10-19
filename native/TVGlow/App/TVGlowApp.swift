import SwiftUI

@main
@MainActor
struct TVGlowApp: App {
    @StateObject private var store = ControlStore()

    var body: some Scene {
        #if os(macOS)
        Window("TV Glow", id: "main") {
            ContentView(store: store).frame(minWidth: 740, idealWidth: 790, maxWidth: 920, minHeight: 610, idealHeight: 730)
        }
        .defaultSize(width: 790, height: 730)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reconnect TV") { Task { await store.connectTV() } }.keyboardShortcut("r", modifiers: [.command])
                Button("Refresh devices") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuControlsView(store: store)
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView(store: store)
        }
        #endif
    }
}
