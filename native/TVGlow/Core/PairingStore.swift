import Foundation
import Security

protocol PairingStoring {
    func key(for host: String) -> String?
    func save(_ key: String, for host: String) throws
    func remove(for host: String)
}

struct PairingStore: PairingStoring {
    let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.anna.tvglow.unknown") {
        // Debug and release apps must never query each other's pairing entries.
        service = bundleIdentifier + ".pairing"
    }

    private func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: host]
    }

    func key(for host: String) -> String? {
        var request = query(host)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String, for host: String) throws {
        let data = Data(key.utf8)
        let result = SecItemUpdate(query(host) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else {
            throw ControlError.device("Could not update the saved TV pairing in Keychain (\(result)).")
        }
        var request = query(host)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(request as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw ControlError.device("Could not save the TV pairing in Keychain (\(added)).")
        }
    }

    func remove(for host: String) { SecItemDelete(query(host) as CFDictionary) }
}
