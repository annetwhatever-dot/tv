import SwiftUI

#if os(macOS)
struct MenuControlsView: View {
    @ObservedObject var store: ControlStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("TV Glow", systemImage: "sun.max.fill").foregroundStyle(GlowTheme.lime)
                Spacer()
                Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help("Open TV Glow")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Brightness"); Spacer(); Text(store.brightness.map { "\($0)%" } ?? "Offline").monospacedDigit() }
                Slider(value: $store.brightnessDraft, in: 0...100, step: 1) { editing in
                    store.editingBrightness = editing
                    if !editing { Task { await store.setBrightness(Int(store.brightnessDraft)) } }
                }.disabled(!store.tvConnected || store.applyingBrightness).accessibilityLabel("TV brightness")
                if !store.tvConnected { Button("Connect TV") { Task { await store.connectTV() } }.disabled(store.tvConnecting) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sonos volume")
                    Spacer()
                    Text(store.volume.map { store.muted ? "Muted · \($0)%" : "\($0)%" } ?? "Offline").monospacedDigit()
                    Button { Task { await store.toggleMute() } } label: { Image(systemName: store.muted ? "speaker.slash" : "speaker.wave.2") }
                        .buttonStyle(.plain).disabled(!store.sonosConnected || store.applyingVolume).help(store.muted ? "Unmute Sonos" : "Mute Sonos")
                }
                Slider(value: $store.volumeDraft, in: 0...100, step: 1) { editing in
                    store.editingVolume = editing
                    if !editing { Task { await store.setVolume(Int(store.volumeDraft)) } }
                }.disabled(!store.sonosConnected || store.applyingVolume).accessibilityLabel("Sonos volume")
            }
            HStack {
                Text("Living room").foregroundStyle(GlowTheme.muted)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(GlowTheme.muted)
            }.font(.system(size: 10))
        }
        .font(.system(size: 12)).padding(20).frame(width: 290)
        .background(GlowTheme.background).foregroundStyle(GlowTheme.ink).tint(GlowTheme.lime).preferredColorScheme(.dark)
        .task { store.start() }
    }
}
#endif
