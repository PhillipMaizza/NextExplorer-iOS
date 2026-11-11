import Foundation

/// Whether a file that has a history is still there: `live`, in the `trashed` bin, or `orphaned`
/// (deleted behind the application's back, so its versions are the only copy left).
public enum VersionedFileState: String, CaseIterable, Sendable {
    case live
    case trashed
    case orphaned
}

/// How the admin list of histories is ordered (`ADMIN_SORTS` in the backend's version store).
public enum VersionedFileSort: String, CaseIterable, Sendable {
    case bytes
    case versions
    case newest
    case path
}

/// A volume a history lives in, as the admin versions routes describe it.
public struct VersionedZone: Equatable, Sendable, Decodable, Identifiable, Hashable {
    public let id: String
    public let kind: TrashZone.Kind
    public let name: String

    public init(id: String, kind: TrashZone.Kind = .volume, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        kind = rawKind.flatMap(TrashZone.Kind.init(rawValue:)) ?? .volume
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

/// One file that has a history, a row of `GET /api/versions/admin/files`.
public struct VersionedFile: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let folder: String
    /// The path a browser could open; `nil` outside a plain volume, where there is no address.
    public let path: String?
    public let state: VersionedFileState
    public let versions: Int
    public let bytes: Int
    public let newest: String?
    public let zone: VersionedZone?

    public init(
        id: String,
        name: String,
        relativePath: String? = nil,
        folder: String = "",
        path: String? = nil,
        state: VersionedFileState = .live,
        versions: Int = 1,
        bytes: Int = 0,
        newest: String? = nil,
        zone: VersionedZone? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath ?? name
        self.folder = folder
        self.path = path
        self.state = state
        self.versions = versions
        self.bytes = bytes
        self.newest = newest
        self.zone = zone
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, relativePath, folder, path, state, versions, bytes, newest, zone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? relativePath
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path)
        let rawState = try container.decodeIfPresent(String.self, forKey: .state)
        state = rawState.flatMap(VersionedFileState.init(rawValue:)) ?? .live
        versions = try container.decodeIfPresent(Int.self, forKey: .versions) ?? 0
        bytes = try container.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        newest = try container.decodeIfPresent(String.self, forKey: .newest)
        zone = try container.decodeIfPresent(VersionedZone.self, forKey: .zone)
    }
}

/// A page of `GET /api/versions/admin/files`, with what the whole filter holds.
public struct VersionedFilesPage: Equatable, Sendable, Decodable {
    public let files: [VersionedFile]
    public let total: Int
    public let totalBytes: Int
    public let totalVersions: Int
    public let limit: Int
    public let offset: Int
    public let zones: [VersionedZone]

    public init(
        files: [VersionedFile] = [],
        total: Int = 0,
        totalBytes: Int = 0,
        totalVersions: Int = 0,
        limit: Int = VersionedFilesPage.defaultPageSize,
        offset: Int = 0,
        zones: [VersionedZone] = []
    ) {
        self.files = files
        self.total = total
        self.totalBytes = totalBytes
        self.totalVersions = totalVersions
        self.limit = limit
        self.offset = offset
        self.zones = zones
    }

    public static let defaultPageSize = 25

    private enum CodingKeys: String, CodingKey {
        case files, total, totalBytes, totalVersions, limit, offset, zones
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decodeIfPresent([VersionedFile].self, forKey: .files) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? files.count
        totalBytes = try container.decodeIfPresent(Int.self, forKey: .totalBytes) ?? 0
        totalVersions = try container.decodeIfPresent(Int.self, forKey: .totalVersions) ?? 0
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? Self.defaultPageSize
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        zones = try container.decodeIfPresent([VersionedZone].self, forKey: .zones) ?? []
    }

    /// The 1 based number of the first row shown, 0 when there are none.
    public var firstShown: Int {
        total == 0 ? 0 : offset + 1
    }

    /// The 1 based number of the last row shown.
    public var lastShown: Int {
        min(total, offset + files.count)
    }

    public var hasPrevious: Bool {
        offset > 0
    }

    public var hasNext: Bool {
        offset + files.count < total
    }
}

/// What the admin versions list is narrowed and ordered by.
public struct VersionedFilesFilter: Equatable, Sendable {
    public var query: String
    public var zoneID: String?
    public var state: VersionedFileState?
    public var sort: VersionedFileSort

    public init(query: String = "", zoneID: String? = nil, state: VersionedFileState? = nil, sort: VersionedFileSort = .bytes) {
        self.query = query
        self.zoneID = zoneID
        self.state = state
        self.sort = sort
    }
}

/// One history and its versions, from `GET /api/versions/admin/files/:id`.
public struct VersionedFileDetail: Equatable, Sendable, Decodable {
    public let versions: [FileVersion]
    public let totalBytes: Int64

    public init(versions: [FileVersion] = [], totalBytes: Int64 = 0) {
        self.versions = versions
        self.totalBytes = totalBytes
    }

    private enum CodingKeys: String, CodingKey {
        case versions, totalBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versions = try container.decodeIfPresent([FileVersion].self, forKey: .versions) ?? []
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
    }
}

/// The answer to deleting versions of a history.
public struct VersionsDeletion: Equatable, Sendable, Decodable {
    public let deleted: Int
    public let remaining: Int
    /// Versions the server could not delete or could not find. It still answers 200 for these,
    /// with a status per version.
    public let failed: Int

    public init(deleted: Int = 0, remaining: Int = 0, failed: Int = 0) {
        self.deleted = deleted
        self.remaining = remaining
        self.failed = failed
    }

    private struct Item: Decodable {
        let status: String?
    }

    private enum CodingKeys: String, CodingKey {
        case deleted, remaining, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deleted = try container.decodeIfPresent(Int.self, forKey: .deleted) ?? 0
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        let items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        failed = items.filter { $0.status == "failed" || $0.status == "not-found" }.count
    }
}
