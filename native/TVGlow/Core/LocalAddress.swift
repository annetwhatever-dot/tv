import Foundation
import CoreFoundation

enum ControlError: LocalizedError {
    case invalidAddress, disconnected, timedOut, missingResource, invalidResponse
    case device(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a local IPv4 address, such as 192.168.2.159."
        case .disconnected: return "The device is disconnected. Switch it on and reconnect."
        case .timedOut: return "The device did not respond. Check its connection and try again."
        case .missingResource: return "The TV pairing manifest is missing from this app."
        case .invalidResponse: return "The device returned an unexpected response."
        case .device(let message): return message
        }
    }
}

enum LocalAddress {
    static func validated(_ input: String) throws -> String {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw ControlError.invalidAddress }
        let values = try parts.map { part -> Int in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part), (0...255).contains(value), String(value) == part
            else { throw ControlError.invalidAddress }
            return value
        }
        guard values[0] == 10 || (values[0] == 172 && (16...31).contains(values[1])) ||
                (values[0] == 192 && values[1] == 168) else { throw ControlError.invalidAddress }
        return host
    }

    static func level(_ value: Any?) throws -> Int {
        let number: Int?
        if let string = value as? String { number = Int(string) }
        else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            let exact = value.doubleValue
            number = exact.isFinite && exact.rounded() == exact ? Int(exact) : nil
        } else { number = nil }
        guard let number, (0...100).contains(number) else { throw ControlError.invalidResponse }
        return number
    }
}
