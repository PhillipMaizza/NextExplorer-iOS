import Foundation

/// One folder's entry from the server's folder size index (the folder size batch route,
/// confirmed against `backend/src/routes/folderSize.js`). `sizeBytes` is null until the indexer has
/// reached the folder; `dirty` marks a size that a running scan is about to replace. The size comes
/// back even for a folder the user may not open.
public struct FolderSize: Equatable, Sendable, Decodable {
    public let sizeBytes: Int64?
    public let indexed: Bool
    public let dirty: Bool
    public let excluded: Bool

    /// The figure to show: indexed, not left out of the index, and actually counted.
    public var shownBytes: Int64? {
        indexed && !excluded ? sizeBytes : nil
    }

    public init(sizeBytes: Int64? = nil, indexed: Bool = false, dirty: Bool = false, excluded: Bool = false) {
        self.sizeBytes = sizeBytes
        self.indexed = indexed
        self.dirty = dirty
        self.excluded = excluded
    }

    private enum CodingKeys: String, CodingKey {
        case sizeBytes, indexed, dirty, excluded
    }

    /// Every field is optional on the wire; a missing or odd value reads as "not known".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizeBytes = (try? container.decode(Int64.self, forKey: .sizeBytes)).flatMap { $0 >= 0 ? $0 : nil }
        indexed = (try? container.decode(Bool.self, forKey: .indexed)) ?? false
        dirty = (try? container.decode(Bool.self, forKey: .dirty)) ?? false
        excluded = (try? container.decode(Bool.self, forKey: .excluded)) ?? false
    }
}
