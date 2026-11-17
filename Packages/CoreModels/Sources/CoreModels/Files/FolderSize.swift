import Foundation

/// One folder's entry from the server's folder size index (the folder size batch route,
/// confirmed against `backend/src/routes/folderSize.js`). The size is reported even for a folder
/// the user may not open (`canEnter` false). `sizeBytes` and `entryCount` are null until the
/// indexer has reached the folder; `dirty` marks a size that a running scan is about to replace.
public struct FolderSize: Equatable, Sendable, Decodable {
    public let path: String
    public let canEnter: Bool
    public let sizeBytes: Int64?
    public let entryCount: Int?
    public let indexed: Bool
    public let dirty: Bool
    public let excluded: Bool

    /// Whether a figure can be shown: indexed, not left out of the index, and actually counted.
    public var hasSize: Bool {
        indexed && !excluded && sizeBytes != nil
    }

    public init(
        path: String,
        canEnter: Bool = true,
        sizeBytes: Int64? = nil,
        entryCount: Int? = nil,
        indexed: Bool = false,
        dirty: Bool = false,
        excluded: Bool = false
    ) {
        self.path = path
        self.canEnter = canEnter
        self.sizeBytes = sizeBytes
        self.entryCount = entryCount
        self.indexed = indexed
        self.dirty = dirty
        self.excluded = excluded
    }

    private enum CodingKeys: String, CodingKey {
        case path, canEnter, sizeBytes, entryCount, indexed, dirty, excluded
    }

    /// Every field but the path is optional on the wire; a missing or odd value reads as "not known".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        canEnter = (try? container.decode(Bool.self, forKey: .canEnter)) ?? false
        sizeBytes = (try? container.decode(Int64.self, forKey: .sizeBytes)).flatMap { $0 >= 0 ? $0 : nil }
        entryCount = (try? container.decode(Int.self, forKey: .entryCount)).flatMap { $0 >= 0 ? $0 : nil }
        indexed = (try? container.decode(Bool.self, forKey: .indexed)) ?? false
        dirty = (try? container.decode(Bool.self, forKey: .dirty)) ?? false
        excluded = (try? container.decode(Bool.self, forKey: .excluded)) ?? false
    }
}
