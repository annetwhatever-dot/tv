import Foundation
import Combine

@MainActor
final class ControlStore: ObservableObject {
    @Published var tvAddress: String
    @Published var sonosAddress: String
    @Published private(set) var tvConnected = false
    @Published private(set) var tvConnecting = false
    @Published private(set) var awaitingTVApproval = false
    @Published private(set) var brightness: Int?
    @Published var brightnessDraft: Double = 0
    @Published var editingBrightness = false
    @Published private(set) var applyingBrightness = false
    @Published private(set) var tvMessage = "Connect your TV to begin."
    @Published private(set) var tvError = false

    @Published private(set) var sonosConnected = false
    @Published private(set) var sonosConnecting = false
    @Published private(set) var sonosName = "Sonos Arc Ultra"
    @Published private(set) var volume: Int?
    @Published var volumeDraft: Double = 0
    @Published var editingVolume = false
    @Published private(set) var applyingVolume = false
    @Published private(set) var muted = false
    @Published private(set) var sonosMessage = "Connecting to your soundbar…"
    @Published private(set) var sonosError = false

    private let tv: TVCommunicating
    private let sonos: SonosCommunicating
    private let vault: PairingStoring
    private let defaults: UserDefaults
    private var tvHost: String?
    private var sonosHost: String?
    private var monitoring: Task<Void, Never>?
    private var started = false

    init(tv: TVCommunicating? = nil, sonos: SonosCommunicating? = nil,
         vault: PairingStoring = PairingStore(), defaults: UserDefaults = .standard) {
        self.tv = tv ?? WebOSClient()
        self.sonos = sonos ?? SonosClient()
        self.vault = vault
        self.defaults = defaults
        self.tvAddress = defaults.string(forKey: "tvAddress") ?? "192.168.2.159"
        self.sonosAddress = defaults.string(forKey: "sonosAddress") ?? "192.168.0.206"
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await connectSonos()
            if vault.key(for: tvAddress) != nil { await connectTV() }
        }
        monitoring = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                await self?.refresh()
                // Local-network permission can be granted after the first request fails.
                // Retry read-only soundbar discovery while it is offline.
                if let self, !self.sonosConnected { await self.connectSonos() }
            }
        }
    }

    func connectTV() async {
        guard !tvConnecting, !applyingBrightness else { return }
        tvConnecting = true
        tvConnected = false
        tvError = false
        awaitingTVApproval = false
        brightness = nil
        tvMessage = "Connecting to LG C1…"
        defer { tvConnecting = false; awaitingTVApproval = false }
        do {
            let host = try LocalAddress.validated(tvAddress)
            let key = try await tv.connect(host: host, key: vault.key(for: host)) { [weak self] in
                self?.awaitingTVApproval = true
                self?.tvMessage = "Choose Accept on the TV’s connection request."
            }
            try vault.save(key, for: host)
            tvHost = host
            defaults.set(host, forKey: "tvAddress")
            let current = try await tv.brightness()
            brightness = current
            brightnessDraft = Double(current)
            tvConnected = true
            tvMessage = "Live from your TV."
        } catch {
            tv.disconnect()
            tvMessage = error.localizedDescription
            tvError = true
        }
    }

    func connectSonos() async {
        guard !sonosConnecting, !applyingVolume else { return }
        sonosConnecting = true
        sonosError = false
        defer { sonosConnecting = false }
        do {
            let host = try LocalAddress.validated(sonosAddress)
            let name = try await sonos.identify(host: host)
            let current = try await sonos.state(host: host)
            sonosHost = host
            defaults.set(host, forKey: "sonosAddress")
            sonosName = name
            updateSonos(current)
            sonosConnected = true
            sonosMessage = "Live from your soundbar."
        } catch {
            sonosConnected = false
            volume = nil
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    func refresh() async {
        if tvConnected && !tvConnecting && !applyingBrightness && !editingBrightness {
            do {
                let value = try await tv.brightness()
                if !applyingBrightness && !editingBrightness {
                    brightness = value
                    brightnessDraft = Double(value)
                }
            } catch {
                tvConnected = false
                tvMessage = "TV disconnected. Switch it on and reconnect."
                tvError = true
            }
        }
        if sonosConnected && !sonosConnecting && !applyingVolume && !editingVolume, let host = sonosHost {
            do {
                let state = try await sonos.state(host: host)
                if !applyingVolume && !editingVolume { updateSonos(state) }
            } catch {
                sonosConnected = false
                sonosMessage = "Soundbar disconnected. Check its network and reconnect."
                sonosError = true
            }
        }
    }

    func setBrightness(_ target: Int) async {
        guard tvConnected, !applyingBrightness, (0...100).contains(target) else { return }
        applyingBrightness = true
        tvError = false
        tvMessage = "Adjusting the glow…"
        defer { applyingBrightness = false }
        do {
            try await tv.setBrightness(target)
            try await Task.sleep(nanoseconds: 300_000_000)
            let actual = try await tv.brightness()
            brightness = actual
            brightnessDraft = Double(actual)
            guard actual == target else {
                throw ControlError.device("The TV kept its previous brightness. Check its Energy Saving setting.")
            }
            tvMessage = "Brightness set to \(actual)%."
        } catch {
            if let brightness { brightnessDraft = Double(brightness) }
            tvMessage = error.localizedDescription
            tvError = true
        }
    }

    func setVolume(_ target: Int) async {
        guard sonosConnected, let host = sonosHost, !applyingVolume, (0...100).contains(target) else { return }
        applyingVolume = true
        sonosError = false
        sonosMessage = "Adjusting volume…"
        defer { applyingVolume = false }
        do {
            try await sonos.setVolume(target, host: host)
            let actual = try await sonos.state(host: host)
            updateSonos(actual)
            guard actual.volume == target else { throw ControlError.device("Sonos kept its previous volume. Check the soundbar’s volume limit.") }
            sonosMessage = "Volume set to \(actual.volume)%."
        } catch {
            if let volume { volumeDraft = Double(volume) }
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    func toggleMute() async {
        guard sonosConnected, let host = sonosHost, !applyingVolume else { return }
        applyingVolume = true
        sonosError = false
        let target = !muted
        defer { applyingVolume = false }
        do {
            try await sonos.setMuted(target, host: host)
            let actual = try await sonos.state(host: host)
            updateSonos(actual)
            guard actual.muted == target else { throw ControlError.device("Sonos did not confirm the mute change.") }
            sonosMessage = actual.muted ? "Soundbar muted." : "Soundbar unmuted."
        } catch {
            sonosMessage = error.localizedDescription
            sonosError = true
        }
    }

    private func updateSonos(_ state: SonosState) {
        volume = state.volume
        volumeDraft = Double(state.volume)
        muted = state.muted
    }

    func forgetTV() {
        guard !tvConnecting, !applyingBrightness else { return }
        if let host = tvHost ?? (try? LocalAddress.validated(tvAddress)) { vault.remove(for: host) }
        tv.disconnect()
        tvConnected = false
        brightness = nil
        tvMessage = "Pairing removed from this device. Connect to pair again."
        tvError = false
    }
}
