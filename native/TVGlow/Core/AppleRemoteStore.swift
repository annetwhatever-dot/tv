import Foundation
import Combine

enum AppleRemotePhase: Equatable {
    case disconnected, connecting, pairing, connected
    case failed(String)

    var isBusy: Bool { self == .connecting || self == .pairing }
}

struct AppleRemoteDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String?
}

struct AppleRemoteSnapshot: Equatable {
    var devices: [AppleRemoteDevice] = []
    var phase: AppleRemotePhase = .disconnected
    var connectedName: String?
    var canSubmitPIN = false
    var keyboardFocused = false
}

enum AppleRemoteCommand: String, CaseIterable {
    case up, down, left, right, select, back, home, playPause, wake
}

@MainActor
protocol AppleRemoteDriving: AnyObject {
    var snapshot: AppleRemoteSnapshot { get }
    func startDiscovery()
    func stopDiscovery()
    func connect(deviceID: String)
    func disconnect()
    func submitPIN(_ pin: String)
    func press(_ command: AppleRemoteCommand)
    func sendText(_ text: String)
}

@MainActor
final class AppleRemoteStore: ObservableObject {
    @Published private(set) var snapshot = AppleRemoteSnapshot()
    @Published var selectedDeviceID: String?
    @Published var pin = ""
    @Published var text = ""
    @Published private(set) var pinSubmitted = false
    @Published private(set) var notice: String?
    @Published private(set) var hasError = false
    private let driver: AppleRemoteDriving
    private let defaults: UserDefaults
    private var observation: Task<Void, Never>?
    private var phaseStarted = Date()
    private var started = false

    init(driver: AppleRemoteDriving? = nil, defaults: UserDefaults = .standard) {
        self.driver = driver ?? NativeAppleRemoteDriver()
        self.defaults = defaults
    }

    var connected: Bool { snapshot.phase == .connected }
    var canPair: Bool { selectedDeviceID != nil && !snapshot.phase.isBusy && !connected }
    var canSubmitPIN: Bool { snapshot.canSubmitPIN && !pinSubmitted && Self.validPIN(pin) != nil }

    var message: String {
        if let notice { return notice }
        switch snapshot.phase {
        case .disconnected:
            return snapshot.devices.isEmpty ? "Looking for Apple TVs on your home network…" : "Choose your Apple TV and connect."
        case .connecting: return "Connecting securely to Apple TV…"
        case .pairing: return snapshot.canSubmitPIN ? "Enter the four-digit code shown on your TV." : "Waiting for the pairing code on your TV…"
        case .connected: return "Ready. Use the pad or remote buttons."
        case .failed(let error): return error
        }
    }

    func start() {
        guard !started else { return }
        started = true
        driver.startDiscovery()
        synchronize()
        observation = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                self?.synchronize()
            }
        }
    }

    func synchronize(now: Date = Date()) {
        var next = driver.snapshot
        if next.phase != snapshot.phase {
            phaseStarted = now
            pinSubmitted = false
            notice = nil
            hasError = false
            if next.phase == .connected {
                pin = ""
                if let selectedDeviceID { defaults.set(selectedDeviceID, forKey: "appleTVDeviceID") }
            }
        }
        let limit: TimeInterval = next.phase == .pairing ? 120 : 25
        if next.phase.isBusy && now.timeIntervalSince(phaseStarted) > limit {
            driver.disconnect()
            next = driver.snapshot
            notice = "Apple TV did not finish connecting. Check its screen and try again."
            hasError = true
            pinSubmitted = false
        }
        if snapshot.keyboardFocused && !next.keyboardFocused { text = "" }
        if next != snapshot { snapshot = next }
        if !snapshot.devices.contains(where: { $0.id == selectedDeviceID }) && !snapshot.phase.isBusy && !connected {
            let preferred = defaults.string(forKey: "appleTVDeviceID")
            selectedDeviceID = snapshot.devices.first(where: { $0.id == preferred })?.id ?? snapshot.devices.first?.id
        }
    }

    func connect() {
        guard canPair, let selectedDeviceID else { return }
        notice = nil; hasError = false; pin = ""; text = ""
        driver.connect(deviceID: selectedDeviceID)
        phaseStarted = Date()
        synchronize()
    }

    func disconnect() {
        driver.disconnect()
        pin = ""; text = ""; pinSubmitted = false; notice = nil; hasError = false
        synchronize()
    }

    func rescan() {
        driver.stopDiscovery()
        driver.startDiscovery()
        synchronize()
    }

    static func validPIN(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) } ? value : nil
    }

    func submitPIN() {
        guard snapshot.canSubmitPIN, !pinSubmitted, let value = Self.validPIN(pin) else {
            notice = "Enter the four-digit code shown on your Apple TV."
            hasError = true
            return
        }
        pinSubmitted = true
        notice = "Verifying the pairing code…"; hasError = false
        driver.submitPIN(value)
    }

    func press(_ command: AppleRemoteCommand) {
        guard connected else { return }
        driver.press(command)
        notice = nil; hasError = false
    }

    func sendText() {
        guard connected, snapshot.keyboardFocused, !text.isEmpty else { return }
        driver.sendText(text)
        text = ""
        notice = "Text sent to Apple TV."; hasError = false
    }

    func stop() {
        observation?.cancel(); observation = nil; started = false
        driver.stopDiscovery()
        disconnect()
    }
}
