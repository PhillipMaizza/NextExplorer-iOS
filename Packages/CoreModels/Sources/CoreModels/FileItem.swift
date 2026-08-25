import Foundation

/// Mirrors an entry returned by `GET /api/browse/*`, confirmed against
/// `backend/src/services/directoryListingService.js`. `kind` is `"directory"` for
/// folders, otherwise the lowercased file extension (or `"unknown"` with none/an
/// overlong one); there is no separate `isDirectory` field from the server.
public struct FileItem: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let dateModified: Date
    public let size: Int64
    public let kind: String
    public let supportsThumbnail: Bool

    public var isDirectory: Bool { kind == "directory" }
    public var id: String { path.isEmpty ? name : "\(path)/\(name)" }

    public init(
        name: String,
        path: String,
        dateModified: Date,
        size: Int64,
        kind: String,
        supportsThumbnail: Bool = false
    ) {
        self.name = name
        self.path = path
        self.dateModified = dateModified
        self.size = size
        self.kind = kind
        self.supportsThumbnail = supportsThumbnail
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, dateModified, size, kind, supportsThumbnail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        size = try container.decode(Int64.self, forKey: .size)
        kind = try container.decode(String.self, forKey: .kind)
        supportsThumbnail = try container.decodeIfPresent(Bool.self, forKey: .supportsThumbnail) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encode(size, forKey: .size)
        try container.encode(kind, forKey: .kind)
        try container.encode(supportsThumbnail, forKey: .supportsThumbnail)
    }
}
