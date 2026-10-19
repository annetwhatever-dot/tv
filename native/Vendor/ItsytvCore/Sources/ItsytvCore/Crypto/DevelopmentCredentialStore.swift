import Foundation

/// Development-only storage inside the app sandbox. Files are not encrypted;
/// directory/file permissions restrict access to the current user. Release uses Keychain.
public struct DevelopmentCredentialStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("credentials.json") }

    public init(namespace: String, root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVGlowDevelopment", isDirectory: true)
        self.directory = base.appendingPathComponent(namespace, isDirectory: true)
    }

    public static func isEnabled(bundleIdentifier: String) -> Bool {
        #if DEBUG
        return bundleIdentifier.hasPrefix("com.anna.tvglow.") && bundleIdentifier.hasSuffix(".debug")
        #else
        return false
        #endif
    }

    private func read() -> [String: Data] {
        guard let data = try? Data(contentsOf: file),
              let values = try? JSONDecoder().decode([String: Data].self, from: data) else { return [:] }
        return values
    }

    public func data(for account: String) -> Data? { read()[account] }
    public func accounts() -> [String] { Array(read().keys) }

    public func save(_ data: Data, for account: String) throws {
        var values = read()
        values[account] = data
        try write(values)
    }

    public func remove(for account: String) throws {
        var values = read()
        values.removeValue(forKey: account)
        try write(values)
    }

    private func write(_ values: [String: Data]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
