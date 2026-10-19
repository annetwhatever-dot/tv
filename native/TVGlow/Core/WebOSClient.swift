import Foundation

@MainActor
protocol TVCommunicating: AnyObject {
    func connect(host: String, key: String?, awaitingApproval: @escaping () -> Void) async throws -> String
    func brightness() async throws -> Int
    func setBrightness(_ value: Int) async throws
    func disconnect()
}

@MainActor
final class WebOSClient: TVCommunicating {
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeout: Task<Void, Never>
        let registration: Bool
    }

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var approval: (() -> Void)?

    func connect(host: String, key: String?, awaitingApproval: @escaping () -> Void) async throws -> String {
        let host = try LocalAddress.validated(host)
        disconnect()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 75
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        self.session = session
        // C1's native LAN WebSocket endpoint. No remote server or account is used.
        let socket = session.webSocketTask(with: URL(string: "ws://\(host):3000")!)
        self.socket = socket
        self.approval = awaitingApproval
        socket.resume()
        receiver = Task { [weak self, weak socket] in
            guard let socket else { return }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    self?.receive(message)
                }
            } catch {
                if !Task.isCancelled { self?.failAll(error) }
            }
        }

        do {
            guard let url = Bundle.main.url(forResource: "WebOSManifest", withExtension: "json"),
                  let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            else { throw ControlError.missingResource }
            var payload: [String: Any] = ["forcePairing": false, "manifest": manifest, "pairingType": "PROMPT"]
            if let key { payload["client-key"] = key }
            let result = try await request(type: "register", payload: payload, timeout: 70)
            guard let newKey = result["client-key"] as? String else { throw ControlError.invalidResponse }
            return newKey
        } catch {
            disconnect()
            throw error
        }
    }

    private func request(type: String = "request", uri: String? = nil, payload: [String: Any], timeout: UInt64 = 7) async throws -> [String: Any] {
        guard let socket else { throw ControlError.disconnected }
        let id = UUID().uuidString
        var message: [String: Any] = ["id": id, "type": type, "payload": payload]
        if let uri { message["uri"] = "ssap://" + uri }
        let bytes = try JSONSerialization.data(withJSONObject: message)
        guard let text = String(data: bytes, encoding: .utf8) else { throw ControlError.invalidResponse }
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: timeout * 1_000_000_000) }
                catch { return }
                self?.complete(id, .failure(ControlError.timedOut))
            }
            pending[id] = Pending(continuation: continuation, timeout: timer, registration: type == "register")
            Task { [weak self] in
                do { try await socket.send(.string(text)) }
                catch { self?.complete(id, .failure(error)) }
            }
        }
    }

    private func receive(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, let entry = pending[id] else { return }
        let type = json["type"] as? String
        let payload = json["payload"] as? [String: Any] ?? [:]
        if type == "error" || (payload["returnValue"] as? Bool) == false {
            let message = payload["errorText"] as? String ?? json["error"] as? String ?? "The TV rejected the request."
            complete(id, .failure(ControlError.device(message)))
        } else if entry.registration && type == "response" {
            approval?()
        } else if !entry.registration || type == "registered" {
            complete(id, .success(payload))
        }
    }

    private func complete(_ id: String, _ result: Result<[String: Any], Error>) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout.cancel()
        entry.continuation.resume(with: result)
    }

    private func failAll(_ error: Error) {
        for id in Array(pending.keys) { complete(id, .failure(error)) }
    }

    func disconnect() {
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        approval = nil
        failAll(ControlError.disconnected)
    }

    func brightness() async throws -> Int {
        // pictureMode is intentionally omitted: C1 rejects that key here.
        let response = try await request(uri: "settings/getSystemSettings", payload: ["category": "picture", "keys": ["backlight"]])
        let settings = response["settings"] as? [String: Any]
        return try LocalAddress.level(settings?["backlight"])
    }

    func setBrightness(_ value: Int) async throws {
        guard (0...100).contains(value) else { throw ControlError.invalidResponse }
        let settings: [String: Any] = ["category": "picture", "settings": ["backlight": value]]
        do {
            _ = try await request(uri: "settings/setSystemSettings", payload: settings)
        } catch ControlError.device(_) {
            // C1 rejects direct writes with a 500/unsupported-key response.
            // Use the same normal-picture-setting fallback as the verified controller.
            let luna = "luna://com.webos.settingsservice/setSystemSettings"
            let callback: [String: Any] = ["uri": luna, "params": settings]
            let alert = try await request(uri: "system.notifications/createAlert", payload: [
                "message": " ", "buttons": [["label": "", "onClick": luna, "params": settings]],
                "onclose": callback, "onfail": callback,
            ])
            guard let id = alert["alertId"] as? String else { throw ControlError.invalidResponse }
            _ = try await request(uri: "system.notifications/closeAlert", payload: ["alertId": id])
        }
    }
}
