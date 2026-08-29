import Foundation

/// Response from `GET /api/usage/*`, confirmed against `backend/src/routes/usage.js`:
/// `size` is `du -sb` of the target folder (recursive bytes), `free`/`total` are `df` of the
/// filesystem it sits on. A denied or failed path comes back all zeros.
public struct StorageUsage: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let free: Int64
    public let total: Int64

    public init(path: String = "", size: Int64 = 0, free: Int64 = 0, total: Int64 = 0) {
        self.path = path
        self.size = size
        self.free = free
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case path, size, free, total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        free = try container.decodeIfPresent(Int64.self, forKey: .free) ?? 0
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? 0
    }

    /// Bytes used on the volume — the folder's recursive size, mirroring the web client.
    public var used: Int64 { size }

    /// Total capacity: the `df` total, or `used + free` when `df` didn't report one.
    public var capacity: Int64 { total > 0 ? total : size + free }

    /// `0...1`, clamped. `0` when there's nothing to divide by.
    public var fraction: Double {
        guard capacity > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(capacity)))
    }

    /// Whether the server actually reported disk figures (vs an all-zero denied response).
    public var isMeaningful: Bool { capacity > 0 }
}
