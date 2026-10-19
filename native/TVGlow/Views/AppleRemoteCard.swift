import SwiftUI

struct AppleRemoteCard: View {
    @ObservedObject var remote: AppleRemoteStore
    @FocusState private var padFocused: Bool

    var body: some View {
        CardContainer {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "appletv.fill").font(.system(size: 22)).foregroundStyle(GlowTheme.lime)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple TV").font(.system(size: 15, weight: .medium))
                        Text(remote.snapshot.connectedName ?? "Your favourite seat. Your remote.")
                            .font(.system(size: 10)).foregroundStyle(GlowTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ConnectionBadge(connected: remote.connected, busy: remote.snapshot.phase.isBusy)
                }

                if remote.connected {
                    HStack {
                        Text("Navigation & playback").font(.system(size: 11)).foregroundStyle(GlowTheme.muted)
                        Spacer()
                        Button("Disconnect") { remote.disconnect() }.font(.system(size: 10)).buttonStyle(.plain)
                            .foregroundStyle(GlowTheme.muted)
                    }
                } else {
                    connectionControls
                }

                if remote.snapshot.phase == .pairing {
                    HStack(spacing: 8) {
                        SecureField("4-digit TV code", text: $remote.pin)
                            .textFieldStyle(.roundedBorder).onSubmit { if remote.canSubmitPIN { remote.submitPIN() } }
                            .accessibilityIdentifier("appleTVPINField")
                        Button(remote.pinSubmitted ? "Verifying…" : "Pair") { remote.submitPIN() }
                            .disabled(!remote.canSubmitPIN).accessibilityIdentifier("appleTVPairPINButton")
                    }
                    .font(.system(size: 12))
                }

                directionPad
                    .disabled(!remote.connected)
                    .opacity(remote.connected ? 1 : 0.4)
                    .padding(.vertical, 2)

                HStack(spacing: 9) {
                    commandButton("Back", symbol: "chevron.backward", command: .back)
                    commandButton("Home", symbol: "house", command: .home)
                    commandButton("Play / pause", symbol: "playpause.fill", command: .playPause)
                }
                .disabled(!remote.connected)

                Divider().overlay(GlowTheme.line)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard").font(.system(size: 13))
                        Text("Type on your TV").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if remote.snapshot.keyboardFocused { Circle().fill(GlowTheme.lime).frame(width: 5, height: 5) }
                    }
                    HStack(spacing: 8) {
                        TextField("Search or enter text…", text: $remote.text)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { remote.sendText() }
                            .disabled(!remote.connected || !remote.snapshot.keyboardFocused)
                            .accessibilityIdentifier("appleTVTextField")
                        Button { remote.sendText() } label: { Image(systemName: "arrow.up") }
                            .disabled(!remote.connected || !remote.snapshot.keyboardFocused || remote.text.isEmpty)
                            .accessibilityLabel("Send text to Apple TV").accessibilityIdentifier("appleTVSendTextButton")
                    }
                    .font(.system(size: 12))
                    Text(remote.snapshot.keyboardFocused ? "Text entry is active on Apple TV." : "Open a search or text field on Apple TV first.")
                        .font(.system(size: 9)).foregroundStyle(GlowTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Text(remote.message).font(.system(size: 10))
                    .foregroundStyle(remote.hasError ? .orange : GlowTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appleTVMessage")
            }
        }
        .task { remote.start() }
    }

    @ViewBuilder private var connectionControls: some View {
        if remote.snapshot.devices.isEmpty {
            HStack {
                Text("No Apple TV found yet").font(.system(size: 11)).foregroundStyle(GlowTheme.muted)
                Spacer()
                RoundControl(symbol: "arrow.clockwise", label: "Search for Apple TVs") { remote.rescan() }
            }
        } else {
            HStack(spacing: 8) {
                Picker("Apple TV", selection: $remote.selectedDeviceID) {
                    ForEach(remote.snapshot.devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .disabled(remote.snapshot.phase.isBusy).accessibilityIdentifier("appleTVDevicePicker")
                if remote.snapshot.phase.isBusy {
                    Button("Cancel") { remote.disconnect() }.font(.system(size: 11)).buttonStyle(.plain)
                } else {
                    Button("Connect") { remote.connect() }.disabled(!remote.canPair)
                        .accessibilityIdentifier("appleTVConnectButton")
                }
            }
            .font(.system(size: 12))
        }
    }

    private var directionPad: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); padButton(.up, symbol: "chevron.up", label: "Up"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
            GridRow { padButton(.left, symbol: "chevron.left", label: "Left"); padButton(.select, symbol: "circle", label: "Select"); padButton(.right, symbol: "chevron.right", label: "Right") }
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); padButton(.down, symbol: "chevron.down", label: "Down"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
        }
        .padding(5)
        .background(.white.opacity(0.035), in: Circle())
        .overlay(Circle().strokeBorder(padFocused ? GlowTheme.lime.opacity(0.5) : GlowTheme.line))
        .focusable().focused($padFocused)
        .onKeyPress(.upArrow) { key(.up) }
        .onKeyPress(.downArrow) { key(.down) }
        .onKeyPress(.leftArrow) { key(.left) }
        .onKeyPress(.rightArrow) { key(.right) }
        .onKeyPress(.return) { key(.select) }
        .onKeyPress(.space) { key(.playPause) }
        .onKeyPress(.escape) { key(.back) }
        .help("Click the pad, then use arrow keys, Return, Space or Escape.")
    }

    private func key(_ command: AppleRemoteCommand) -> KeyPress.Result {
        guard remote.connected else { return .ignored }
        remote.press(command)
        return .handled
    }

    private func padButton(_ command: AppleRemoteCommand, symbol: String, label: String) -> some View {
        Button {
            remote.press(command)
            padFocused = true
        } label: {
            Group {
                if command == .select {
                    Text("OK").font(.system(size: 12, weight: .semibold)).frame(width: 48, height: 48)
                        .background(GlowTheme.lime.opacity(0.12), in: Circle()).foregroundStyle(GlowTheme.lime)
                } else { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
            }
            .frame(width: 58, height: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Apple TV \(label)")
        .accessibilityIdentifier("appleTV_\(command.rawValue)")
    }

    private func commandButton(_ title: String, symbol: String, command: AppleRemoteCommand) -> some View {
        Button { remote.press(command) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 9))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(GlowTheme.line))
        }
        .buttonStyle(.plain).accessibilityLabel("Apple TV \(title)")
        .accessibilityIdentifier("appleTV_\(command.rawValue)")
    }
}
