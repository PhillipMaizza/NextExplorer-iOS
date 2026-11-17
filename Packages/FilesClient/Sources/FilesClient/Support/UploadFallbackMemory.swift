import Foundation

/// The chunk size a server origin taught this device, kept per origin because a public address
/// and a LAN address sit behind different proxies.
struct UploadFallbackMemory {
    private static let keyPrefix = "uploadFallbackChunkMiB."
    private let key: String
    private let defaults: UserDefaults

    init(serverURL: URL, defaults: UserDefaults = .standard) {
        let origin = [serverURL.host, serverURL.port.map(String.init)].compactMap(\.self).joined(separator: ":")
        key = Self.keyPrefix + origin
        self.defaults = defaults
    }

    var mebibytes: Int? {
        get { defaults.integer(forKey: key) > 0 ? defaults.integer(forKey: key) : nil }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
