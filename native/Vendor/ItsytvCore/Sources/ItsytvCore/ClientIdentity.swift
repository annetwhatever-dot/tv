import Foundation

/// TV Glow host identity; protocol code remains attributed to ItsytvCore.
enum ClientIdentity {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "TV Glow"
    }
}
