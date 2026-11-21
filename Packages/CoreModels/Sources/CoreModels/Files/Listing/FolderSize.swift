import Foundation

/// One folder's entry from the server's folder size index (the folder size batch route,
/// confirmed against `backend/src/routes/folderSize.js`). `sizeBytes` is null until the indexer has
/// reached the folder; `isDirty` marks a size that a running scan is about to replace. The size comes
/// back even for a folder the user may not open.
public struct FolderSize: Equatable, Sendable, Decodable {
    public let sizeBytes: Int64?
    public let isIndexed: Bool
    public let isDirty: Bool
    public let isExcluded: Bool

    /// The figure to show: indexed, not left out of the index, and actually counted.
    public var shownBytes: Int64? {
        isIndexed && !isExcluded ? sizeBytes : nil
    }

    public init(sizeBytes: Int64? = nil, isIndexed: Bool = false, isDirty: Bool = false, isExcluded: Bool = false) {
        self.sizeBytes = sizeBytes
        self.isIndexed = isIndexed
        self.isDirty = isDirty
        self.isExcluded = isExcluded
    }

    private enum CodingKeys: String, CodingKey {
        case sizeBytes
        case isIndexed = "indexed"
        case isDirty = "dirty"
        case isExcluded = "excluded"
    }

    /// Every field is optional on the wire; a missing or odd value reads as "not known".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizeBytes = (try? container.decode(Int64.self, forKey: .sizeBytes)).flatMap { $0 >= 0 ? $0 : nil }
        isIndexed = (try? container.decode(Bool.self, forKey: .isIndexed)) ?? false
        isDirty = (try? container.decode(Bool.self, forKey: .isDirty)) ?? false
        isExcluded = (try? container.decode(Bool.self, forKey: .isExcluded)) ?? false
    }
}
