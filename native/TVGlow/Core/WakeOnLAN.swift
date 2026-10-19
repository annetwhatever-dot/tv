import Foundation
import Network
import Darwin

@MainActor
protocol TVWakeSending {
    func send(host: String, mac: String) throws
    func isReachable(host: String) async -> Bool
}

struct WakeOnLAN: TVWakeSending {
    static func packet(mac: String) throws -> Data {
        let parts = mac.replacingOccurrences(of: "-", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { throw ControlError.device("Enter the TV’s six-part MAC address in Connections.") }
        let bytes = parts.compactMap { part -> UInt8? in
            guard part.count == 2, part.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
            return UInt8(part, radix: 16)
        }
        guard bytes.count == 6, bytes != Array(repeating: 0, count: 6), bytes[0] & 1 == 0 else {
            throw ControlError.device("Enter a valid TV MAC address in Connections.")
        }
        var packet = Data(repeating: 0xff, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    func send(host: String, mac: String) throws {
        let host = try LocalAddress.validated(host)
        let packet = try Self.packet(mac: mac)
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw ControlError.device("Could not open the TV wake connection.") }
        defer { close(descriptor) }
        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else {
            throw ControlError.device("Could not enable Wake-on-LAN broadcasts.")
        }
        // Unicast can reach a routed TV while its router still knows the MAC.
        // Limited broadcast also reaches devices on the Mac’s local network.
        var delivered = false
        for destination in [host, "255.255.255.255"] {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(9).bigEndian
            guard inet_pton(AF_INET, destination, &address.sin_addr) == 1 else { continue }
            let result = packet.withUnsafeBytes { buffer in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            delivered = delivered || result == packet.count
        }
        guard delivered else { throw ControlError.device("Wake packet could not be sent. Check local network access.") }
    }

    func isReachable(host: String) async -> Bool {
        await TCPProbe.check(host: host)
    }
}

@MainActor
private final class TCPProbe {
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?

    private init(host: String) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: 3000, using: .tcp)
    }

    static func check(host: String) async -> Bool {
        let probe = TCPProbe(host: host)
        return await withCheckedContinuation { continuation in
            probe.continuation = continuation
            probe.connection.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .ready: probe.finish(true)
                    case .failed, .cancelled: probe.finish(false)
                    default: break
                    }
                }
            }
            probe.timeout = Task {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                probe.finish(false)
            }
            probe.connection.start(queue: .main)
        }
    }

    private func finish(_ value: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: value)
    }
}
