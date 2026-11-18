import Foundation

/// `GET /api/trash` (`listItems` in the backend's trash service): what the signed in person's
/// trash holds, newest first. Listed even while the trash is off, since leftovers can still be restored.
public struct TrashListing: Decodable, Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionDays: Int?
    public let items: [TrashItem]

    public init(isEnabled: Bool, retentionDays: Int?, items: [TrashItem]) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, retentionDays, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays)
        items = try container.decodeIfPresent([TrashItem].self, forKey: .items) ?? []
    }
}

/// One deleted item (`present` in the backend's trash service).
public struct TrashItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let deletedAt: Date?
    public let expiresAt: Date?
    public let deletedBy: DeletedBy
    public let location: Location?
    /// A folder this person can open to see where the item was, `personal/...` or a volume path.
    public let openPath: String?
    /// `false` while the volume holding it is not mounted: nothing can be done with it but forget it.
    public let isAvailable: Bool
    /// Share links switched off with the item, which a restore can bring back.
    public let shareCount: Int

    public init(
        id: String,
        name: String,
        isDirectory: Bool = false,
        size: Int64? = nil,
        deletedAt: Date? = nil,
        expiresAt: Date? = nil,
        deletedBy: DeletedBy = DeletedBy(label: nil, isYou: true),
        location: Location? = nil,
        openPath: String? = nil,
        isAvailable: Bool = true,
        shareCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.deletedAt = deletedAt
        self.expiresAt = expiresAt
        self.deletedBy = deletedBy
        self.location = location
        self.openPath = openPath
        self.isAvailable = isAvailable
        self.shareCount = shareCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, size, deletedAt, expiresAt, deletedBy, location, openPath, available, shareCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDirectory = try container.decodeIfPresent(String.self, forKey: .kind) == TrashEntry.directoryKind
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt).flatMap(ServerTimestamp.date(from:))
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt).flatMap(ServerTimestamp.date(from:))
        deletedBy = try container.decodeIfPresent(DeletedBy.self, forKey: .deletedBy) ?? DeletedBy(
            label: nil,
            isYou: false
        )
        location = try container.decodeIfPresent(Location.self, forKey: .location)
        openPath = try container.decodeIfPresent(String.self, forKey: .openPath)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        shareCount = try container.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0
    }

    /// Whole days left before the server removes it for good, never negative; `nil` when unknown.
    public func daysUntilRemoval(now: Date, calendar: Calendar) -> Int? {
        guard let expiresAt else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expiresAt)
        ).day
        return days.map { max(0, $0) }
    }

    public struct DeletedBy: Decodable, Equatable, Sendable {
        /// The account name, or `shareLinkLabel` for a guest; `nil` when unknown.
        public let label: String?
        public let isYou: Bool

        public static let shareLinkLabel = "share-link"

        public init(label: String?, isYou: Bool) {
            self.label = label
            self.isYou = isYou
        }

        private enum CodingKeys: String, CodingKey {
            case label, isYou
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decodeIfPresent(String.self, forKey: .label)
            isYou = try container.decodeIfPresent(Bool.self, forKey: .isYou) ?? false
        }
    }

    /// Where it was deleted from: a personal folder, or a volume by name, and the folder inside it.
    public struct Location: Decodable, Equatable, Sendable {
        public let isPersonal: Bool
        public let name: String?
        public let parent: String

        public init(isPersonal: Bool, name: String?, parent: String) {
            self.isPersonal = isPersonal
            self.name = name
            self.parent = parent
        }

        private enum CodingKeys: String, CodingKey {
            case kind, name, parent
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isPersonal = try container.decodeIfPresent(String.self, forKey: .kind) == "personal"
            name = try container.decodeIfPresent(String.self, forKey: .name)
            parent = try container.decodeIfPresent(String.self, forKey: .parent) ?? ""
        }
    }
}

/// `GET /api/trash/items/:id/entries`: what a deleted folder holds at a path inside it.
public struct TrashFolderListing: Decodable, Equatable, Sendable {
    public let item: TrashItem
    public let path: String
    public let entries: [TrashEntry]

    public init(item: TrashItem, path: String, entries: [TrashEntry]) {
        self.item = item
        self.path = path
        self.entries = entries
    }
}

public struct TrashEntry: Decodable, Equatable, Identifiable, Sendable {
    static let directoryKind = "directory"

    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modifiedAt: Date?
    public let shareCount: Int

    public var id: String {
        name
    }

    public init(
        name: String,
        isDirectory: Bool = false,
        size: Int64? = nil,
        modifiedAt: Date? = nil,
        shareCount: Int = 0
    ) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.shareCount = shareCount
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, size, modifiedAt, shareCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isDirectory = try container.decodeIfPresent(String.self, forKey: .kind) == Self.directoryKind
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
            .flatMap(ServerTimestamp.date(from:))
        shareCount = try container.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0
    }

    /// The path of this entry inside the deleted folder, given the folder path being shown.
    public func path(in folderPath: String) -> String {
        folderPath.isEmpty ? name : "\(folderPath)/\(name)"
    }
}

/// What to do with the share links a restored item kept in the trash. The server drops them when
/// the request says nothing, so the app always sends a choice.
public enum ShareLinkChoice: String, Encodable, Equatable, Sendable {
    case restore
    case drop
}

/// The per item answer of restore, restore into a folder and delete for good.
public struct TrashActionResult: Decodable, Equatable, Sendable {
    public let items: [Entry]

    public init(items: [Entry]) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Entry].self, forKey: .items) ?? []
    }

    public var succeeded: [Entry] {
        items.filter(\.status.isSuccess)
    }

    public var failed: [Entry] {
        items.filter { !$0.status.isSuccess }
    }

    public var sharesRestored: Int {
        items.reduce(0) { $0 + $1.sharesRestored }
    }

    public var sharesDropped: Int {
        items.reduce(0) { $0 + $1.sharesDropped }
    }

    public struct Entry: Decodable, Equatable, Sendable {
        /// The item id, or for an entry of a deleted folder its path inside the folder.
        public let key: String
        public let status: Status
        public let name: String?
        public let restoredName: String?
        /// The folder a restored item went back into, when the server lets this user open it.
        public let path: String?
        public let isRenamed: Bool
        public let sharesRestored: Int
        public let sharesDropped: Int

        public init(
            key: String,
            status: Status,
            name: String? = nil,
            restoredName: String? = nil,
            path: String? = nil,
            isRenamed: Bool = false,
            sharesRestored: Int = 0,
            sharesDropped: Int = 0
        ) {
            self.key = key
            self.status = status
            self.name = name
            self.restoredName = restoredName
            self.path = path
            self.isRenamed = isRenamed
            self.sharesRestored = sharesRestored
            self.sharesDropped = sharesDropped
        }

        private enum CodingKeys: String, CodingKey {
            case id, entry, status, reason, name, restoredName, path, renamed, sharesRestored, sharesDropped
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .entry)
                ?? ""
            let status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self.status = Status(serverValue: status, reason: reason)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            restoredName = try container.decodeIfPresent(String.self, forKey: .restoredName)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            isRenamed = try container.decodeIfPresent(Bool.self, forKey: .renamed) ?? false
            sharesRestored = try container.decodeIfPresent(Int.self, forKey: .sharesRestored) ?? 0
            sharesDropped = try container.decodeIfPresent(Int.self, forKey: .sharesDropped) ?? 0
        }
    }

    public enum Status: Equatable, Sendable {
        case restored, purged, forgotten
        case forbidden, destinationForbidden, blocked, invalidDestination, unavailable, busy, lost
        case notFound, cancelled, unknown

        init(serverValue: String, reason: String?) {
            switch serverValue {
            case "restored": self = .restored
            case "purged": self = .purged
            case "forgotten": self = .forgotten
            case "forbidden": self = reason == "destination" ? .destinationForbidden : .forbidden
            case "blocked": self = reason == "invalid-destination" ? .invalidDestination : .blocked
            case "unavailable": self = .unavailable
            case "busy": self = .busy
            case "lost", "lost-copy", "missing": self = .lost
            case "not-found": self = .notFound
            case "cancelled": self = .cancelled
            default: self = .unknown
            }
        }

        public var isSuccess: Bool {
            self == .restored || self == .purged || self == .forgotten
        }
    }
}

/// `POST /api/trash/empty`: how many items went, and how many could not.
public struct TrashEmptySummary: Decodable, Equatable, Sendable {
    public let purged: Int
    public let unavailable: Int
    public let failed: Int

    public init(purged: Int, unavailable: Int = 0, failed: Int = 0) {
        self.purged = purged
        self.unavailable = unavailable
        self.failed = failed
    }

    public var leftBehind: Int {
        unavailable + failed
    }
}

/// `GET /api/trash/items/:id/text`: a text file in the trash, read only.
public struct TrashText: Decodable, Equatable, Sendable {
    public let name: String
    public let content: String

    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

/// What a restore acts on: whole items by id, or entries inside one deleted folder by their paths in it.
public enum TrashTarget: Equatable, Sendable {
    case items([TrashItem.ID])
    case entries(itemID: TrashItem.ID, paths: [String])

    public var count: Int {
        switch self {
        case let .items(ids): ids.count
        case let .entries(_, paths): paths.count
        }
    }
}
