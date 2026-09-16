import FilesClient
import Foundation

/// Whether the list currently on screen came from the server this session (`.live`) or from a
/// saved offline copy (`.cached`, carrying when it was last fetched so the UI can say "5m ago").
/// The Favorites and Shared tabs use this the way `BrowseFeature` uses its own `DataSource`.
public enum CachedListSource: Equatable, Sendable {
    case live
    case cached(fetchedAt: Date)
}

/// Shared "5 minutes ago" formatter for the offline "saved copy" banners, matching the wording
/// `BrowseContentView` already uses.
@MainActor
enum OfflineRelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Thin typed wrapper over `JSONCacheStore` for the list tabs: encode/decode the Codable payload
/// and build the per server cache key in one place, so Favorites and Shared stay consistent.
enum ListCache {
    static func key(_ namespace: String, serverURL: URL) -> String {
        "\(namespace)|\(serverURL.absoluteString)"
    }

    static func load<T: Decodable>(_ store: JSONCacheStore, _ namespace: String, serverURL: URL, as _: T.Type) -> (value: T, fetchedAt: Date)? {
        guard
            let payload = store.read(key: key(namespace, serverURL: serverURL)),
            let value = try? JSONDecoder().decode(T.self, from: payload.data)
        else { return nil }
        return (value, payload.fetchedAt)
    }

    static func save(_ store: JSONCacheStore, _ namespace: String, serverURL: URL, value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.write(key: key(namespace, serverURL: serverURL), data: data)
    }
}
