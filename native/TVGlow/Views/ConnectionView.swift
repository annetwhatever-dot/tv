import SwiftUI

struct ConnectionView: View {
    @ObservedObject var store: ControlStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connections").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Your devices, close at hand.").font(.system(size: 12)).foregroundStyle(GlowTheme.muted)
                }
                Spacer()
                RoundControl(symbol: "xmark", label: "Close connections") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("LG C1 television", systemImage: "tv").font(.system(size: 13, weight: .medium))
                TextField("TV IP address", text: $store.tvAddress).textFieldStyle(.roundedBorder)
                    .disabled(store.tvConnecting).accessibilityIdentifier("tvAddressField")
                Text("Choose Accept on the TV when pairing for the first time. Pairing is saved in this device’s Keychain.")
                    .font(.system(size: 11)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(store.tvConnecting ? "Connecting…" : "Connect TV") { Task { await store.connectTV() } }
                        .disabled(store.tvConnecting || store.applyingBrightness)
                    Spacer()
                    Button("Forget pairing") { store.forgetTV() }.buttonStyle(.plain).foregroundStyle(GlowTheme.muted)
                        .disabled(store.tvConnecting || store.applyingBrightness)
                }
                Text(store.tvMessage).font(.system(size: 11)).foregroundStyle(store.tvError ? .orange : GlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(GlowTheme.line)
            VStack(alignment: .leading, spacing: 9) {
                Label("Sonos soundbar", systemImage: "hifispeaker").font(.system(size: 13, weight: .medium))
                TextField("Sonos IP address", text: $store.sonosAddress).textFieldStyle(.roundedBorder)
                    .disabled(store.sonosConnecting).accessibilityIdentifier("sonosAddressField")
                Button(store.sonosConnecting ? "Connecting…" : "Connect Sonos") { Task { await store.connectSonos() } }
                    .disabled(store.sonosConnecting || store.applyingVolume)
                Text(store.sonosMessage).font(.system(size: 11)).foregroundStyle(store.sonosError ? .orange : GlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Connect to the home network that can reach both devices. No Mac server is needed.")
                .font(.system(size: 11)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(idealWidth: 420)
        .background(GlowTheme.background).foregroundStyle(GlowTheme.ink).tint(GlowTheme.lime).preferredColorScheme(.dark)
    }
}
