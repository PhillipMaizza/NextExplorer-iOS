import Foundation

public struct DeleteImpact: Decodable, Equatable, Sendable {
    public let shareCount: Int
    /// `nil` on a server older than the trash, which deletes for good.
    public let trash: TrashPlan?

    public init(shareCount: Int, trash: TrashPlan? = nil) {
        self.shareCount = shareCount
        self.trash = trash
    }

    /// Whether a delete of these items would send any of them to the trash.
    public var hasTrashBoundItems: Bool {
        (trash?.trashCount ?? 0) > 0
    }

    /// The `trash` object: the server's trash settings and, per item, trash or gone for good.
    public struct TrashPlan: Decodable, Equatable, Sendable {
        public let isEnabled: Bool
        public let retentionDays: Int?
        public let items: [Disposition]

        public init(isEnabled: Bool, retentionDays: Int?, items: [Disposition]) {
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
            items = try container.decodeIfPresent([Disposition].self, forKey: .items) ?? []
        }

        public var trashCount: Int {
            items.count(where: \.isTrashBound)
        }

        public var permanentCount: Int {
            items.count - trashCount
        }

        /// The distinct reasons the items that skip the trash give, in the order they first appear.
        public var permanentReasons: [TrashRefusal] {
            var seen: [TrashRefusal] = []
            for item in items where !item.isTrashBound {
                if let reason = item.reason, !seen.contains(reason) {
                    seen.append(reason)
                }
            }
            return seen
        }
    }

    public struct Disposition: Decodable, Equatable, Sendable {
        public let path: String
        /// `disposition` is `trash`; anything else, an unknown value included, is read as gone for good.
        public let isTrashBound: Bool
        public let reason: TrashRefusal?
        public let shareCount: Int

        public init(path: String, isTrashBound: Bool, reason: TrashRefusal? = nil, shareCount: Int = 0) {
            self.path = path
            self.isTrashBound = isTrashBound
            self.reason = reason
            self.shareCount = shareCount
        }

        private enum CodingKeys: String, CodingKey {
            case path, disposition, reason, shareCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            isTrashBound = try container.decodeIfPresent(String.self, forKey: .disposition) == "trash"
            reason = try container.decodeIfPresent(String.self, forKey: .reason).map(TrashRefusal.init(serverValue:))
            shareCount = try container.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0
        }
    }
}

/// Why an item cannot go to the trash (`describeTargets` and `moveToTrash` in the backend's trash service).
public enum TrashRefusal: String, Equatable, Sendable, CaseIterable {
    case disabled
    case otherDevice = "other-device"
    case tooLarge = "too-large"
    case zoneRoot = "zone-root"
    case zoneUnwritable = "zone-unwritable"
    case noZone = "no-zone"
    case unknown

    public init(serverValue: String) {
        self = Self(rawValue: serverValue) ?? .unknown
    }
}

/// The answer of `DELETE /api/files`: what happened to each item. An item the trash refused is
/// `kept`, still on disk, for the user to delete for good or leave.
public struct DeleteOutcome: Decodable, Equatable, Sendable {
    public let items: [Entry]

    public init(items: [Entry] = []) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }

    /// An older server answers `{ success: true }` with no items: everything was deleted.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Entry].self, forKey: .items) ?? []
    }

    /// The answers for items still on disk. Every other item asked for is gone.
    public var kept: [Entry] {
        items.filter { $0.status == .kept }
    }

    public func trashed(of requested: [FileItem]) -> [FileUndoEntry.TrashedItem] {
        zip(requested, items).compactMap { item, entry in
            guard entry.status == .trashed, let trashID = entry.trashItemID else { return nil }
            return FileUndoEntry.TrashedItem(item: item, trashID: trashID)
        }
    }

    /// The requested items still on disk. The server answers in the order it was asked, so answers
    /// pair with requests by position.
    public func kept(of requested: [FileItem]) -> [FileItem] {
        zip(requested, items).filter { $0.1.status == .kept }.map(\.0)
    }

    public var trashedCount: Int {
        items.count { $0.status == .trashed }
    }

    public struct Entry: Decodable, Equatable, Sendable {
        public enum Status: String, Equatable, Sendable {
            case trashed, deleted, missing, kept, unknown
        }

        public let path: String
        public let status: Status
        public let reason: TrashRefusal?
        public let size: Int64?
        public let budgetBytes: Int64?
        public let trashItemID: String?

        public init(
            path: String,
            status: Status,
            reason: TrashRefusal? = nil,
            size: Int64? = nil,
            budgetBytes: Int64? = nil,
            trashItemID: String? = nil
        ) {
            self.path = path
            self.status = status
            self.reason = reason
            self.size = size
            self.budgetBytes = budgetBytes
            self.trashItemID = trashItemID
        }

        private enum CodingKeys: String, CodingKey {
            case path, status, reason, size, budgetBytes
            case trashItemID = "trashItemId"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            status = try Status(rawValue: container.decodeIfPresent(String.self, forKey: .status) ?? "") ?? .unknown
            reason = try container.decodeIfPresent(String.self, forKey: .reason).map(TrashRefusal.init(serverValue:))
            size = try container.decodeIfPresent(Int64.self, forKey: .size)
            budgetBytes = try container.decodeIfPresent(Int64.self, forKey: .budgetBytes)
            trashItemID = try container.decodeIfPresent(String.self, forKey: .trashItemID)
        }
    }
}
