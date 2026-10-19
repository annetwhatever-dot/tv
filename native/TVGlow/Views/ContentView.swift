import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ControlStore
    @State private var showingConnections = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header.padding(.bottom, 3)
                deviceControls
                HStack(spacing: 6) {
                    Image(systemName: "wifi").font(.system(size: 10))
                    Text("At home, in your element.").font(.system(size: 11))
                }
                .foregroundStyle(GlowTheme.muted).padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
        }
        .background(GlowTheme.background)
        .foregroundStyle(GlowTheme.ink)
        .tint(GlowTheme.lime)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingConnections) { ConnectionView(store: store) }
        .task { store.start() }
    }

    private var maximumWidth: CGFloat {
        #if os(macOS)
        850
        #else
        500
        #endif
    }

    @ViewBuilder private var deviceControls: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 18) {
            BrightnessCard(store: store, showConnections: { showingConnections = true }).frame(maxWidth: .infinity)
            VolumeCard(store: store, showConnections: { showingConnections = true }).frame(maxWidth: .infinity)
        }
        #else
        BrightnessCard(store: store, showConnections: { showingConnections = true })
        VolumeCard(store: store, showConnections: { showingConnections = true })
        #endif
    }

    private var header: some View {
        HStack {
            Image(systemName: "sun.max.fill").font(.system(size: 24, weight: .light)).foregroundStyle(GlowTheme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text("TV Glow").font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("A little light. A little atmosphere.").font(.system(size: 11)).foregroundStyle(GlowTheme.muted)
            }
            Spacer()
            RoundControl(symbol: "slider.horizontal.3", label: "Connections") { showingConnections = true }
                .accessibilityIdentifier("connectionsButton")
        }
    }
}

struct BrightnessCard: View {
    @ObservedObject var store: ControlStore
    let showConnections: () -> Void

    var body: some View {
        CardContainer {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Living room").font(.system(size: 15, weight: .medium))
                        Text("LG C1 · OLED brightness").font(.system(size: 10)).foregroundStyle(GlowTheme.muted)
                    }
                    Spacer()
                    ConnectionBadge(connected: store.tvConnected, busy: store.tvConnecting)
                }
                GlowOrb(level: store.brightnessDraft).frame(height: 110).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(store.brightness == nil ? "—" : "\(Int(store.brightnessDraft))")
                        .font(.system(size: 58, weight: .ultraLight, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 20, weight: .light)).foregroundStyle(GlowTheme.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Brightness \(store.brightness.map { "\($0) percent" } ?? "unavailable")")
                Text(store.editingBrightness ? "Release to set brightness" : "OLED pixel brightness")
                    .font(.system(size: 10)).foregroundStyle(GlowTheme.muted).padding(.top, 2).padding(.bottom, 16)
                HStack(spacing: 12) {
                    RoundControl(symbol: "minus", label: "Dim brightness by 5") { set(max(0, Int(store.brightnessDraft) - 5)) }
                    Slider(value: $store.brightnessDraft, in: 0...100, step: 1) { editing in
                        store.editingBrightness = editing
                        if !editing { set(Int(store.brightnessDraft)) }
                    }
                    .accessibilityLabel("TV brightness").accessibilityValue("\(Int(store.brightnessDraft)) percent")
                    .accessibilityIdentifier("brightnessSlider")
                    RoundControl(symbol: "plus", label: "Increase brightness by 5") { set(min(100, Int(store.brightnessDraft) + 5)) }
                }
                .disabled(!store.tvConnected || store.applyingBrightness)
                HStack(spacing: 10) {
                    preset("Night", symbol: "moon", value: 15)
                    preset("Everyday", symbol: "sun.horizon", value: 45)
                    preset("Bright", symbol: "sun.max", value: 80)
                }
                .padding(.top, 17)
                .disabled(!store.tvConnected || store.applyingBrightness)
                if !store.tvConnected {
                    Button { Task { await store.connectTV() } } label: {
                        HStack(spacing: 8) {
                            if store.tvConnecting { ProgressView().controlSize(.small) }
                            Text(store.tvConnecting ? (store.awaitingTVApproval ? "Accept on your TV" : "Connecting…") : "Connect TV")
                        }.font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11)
                    }
                    .buttonStyle(.plain).background(GlowTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlowTheme.lime).padding(.top, 15).disabled(store.tvConnecting)
                    .accessibilityIdentifier("connectTVButton")
                }
                Text(store.tvMessage).font(.system(size: 10)).foregroundStyle(store.tvError ? .orange : GlowTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 13)
                    .accessibilityIdentifier("tvMessage")
            }
        }
    }

    private func set(_ value: Int) { Task { await store.setBrightness(value) } }

    private func preset(_ title: String, symbol: String, value: Int) -> some View {
        let active = store.brightness == value
        return Button { set(value) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light))
                Text(title).font(.system(size: 10, weight: .medium))
                Text("\(value)%").font(.system(size: 9)).opacity(0.65)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(active ? GlowTheme.lime : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(active ? GlowTheme.lime : GlowTheme.line))
            .foregroundStyle(active ? GlowTheme.background : GlowTheme.ink)
        }
        .buttonStyle(.plain).accessibilityLabel("\(title), brightness \(value) percent")
    }
}

struct GlowOrb: View {
    let level: Double
    var body: some View {
        ZStack {
            Circle().fill(GlowTheme.lime.opacity(0.10 + level / 800)).blur(radius: 25).frame(width: 115, height: 115)
            Circle().stroke(GlowTheme.lime.opacity(0.045), lineWidth: 1).frame(width: 144)
            Circle().stroke(GlowTheme.lime.opacity(0.09), lineWidth: 1).frame(width: 112)
            Circle().fill(RadialGradient(colors: [Color(red: 0.96, green: 0.99, blue: 0.83), GlowTheme.lime, Color(red: 0.39, green: 0.47, blue: 0.29)], center: .init(x: 0.3, y: 0.2), startRadius: 0, endRadius: 85))
                .frame(width: 78, height: 78).brightness(-0.26 + level / 380)
                .shadow(color: GlowTheme.lime.opacity(0.06 + level / 900), radius: 25)
        }
        .accessibilityHidden(true)
    }
}

struct VolumeCard: View {
    @ObservedObject var store: ControlStore
    let showConnections: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Image(systemName: "hifispeaker.fill").font(.system(size: 19, weight: .light)).foregroundStyle(GlowTheme.lime)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sound").font(.system(size: 15, weight: .medium))
                        Text(store.sonosName).font(.system(size: 10)).foregroundStyle(GlowTheme.muted)
                    }
                    Spacer()
                    ConnectionBadge(connected: store.sonosConnected, busy: store.sonosConnecting)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.volume == nil ? "—" : "\(Int(store.volumeDraft))")
                        .font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                    Text(store.muted ? "Muted" : "Volume").font(.system(size: 11)).foregroundStyle(GlowTheme.muted)
                    Spacer()
                    Button { Task { await store.toggleMute() } } label: {
                        Label(store.muted ? "Unmute" : "Mute", systemImage: store.muted ? "speaker.slash.fill" : "speaker.wave.2")
                            .font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.055), in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(!store.sonosConnected || store.applyingVolume)
                    .accessibilityIdentifier("muteButton")
                }
                HStack(spacing: 12) {
                    RoundControl(symbol: "minus", label: "Lower volume by 1") { set(max(0, Int(store.volumeDraft) - 1)) }
                    Slider(value: $store.volumeDraft, in: 0...100, step: 1) { editing in
                        store.editingVolume = editing
                        if !editing { set(Int(store.volumeDraft)) }
                    }
                    .accessibilityLabel("Sonos volume").accessibilityValue("\(Int(store.volumeDraft)) percent")
                    .accessibilityIdentifier("volumeSlider")
                    RoundControl(symbol: "plus", label: "Increase volume by 1") { set(min(100, Int(store.volumeDraft) + 1)) }
                }
                .disabled(!store.sonosConnected || store.applyingVolume)
                if !store.sonosConnected && !store.sonosConnecting {
                    Button("Reconnect soundbar") { Task { await store.connectSonos() } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(GlowTheme.lime)
                }
                Text(store.sonosMessage).font(.system(size: 10)).foregroundStyle(store.sonosError ? .orange : GlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("sonosMessage")
            }
        }
    }

    private func set(_ value: Int) { Task { await store.setVolume(value) } }
}
