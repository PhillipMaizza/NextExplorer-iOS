import Foundation

public struct ArchiveListing: Equatable, Sendable, Decodable {
    public let inside: String
    public let entries: [ArchiveListingEntry]

    public init(inside: String, entries: [ArchiveListingEntry]) {
        self.inside = inside
        self.entries = entries
    }
}

public struct ArchiveListingEntry: Equatable, Sendable, Decodable, Identifiable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let isEncrypted: Bool

    public var id: String {
        path
    }

    public var kind: String {
        isDirectory ? FileItem.directoryKind : (name as NSString).pathExtension.lowercased()
    }

    public init(path: String, name: String, isDirectory: Bool, size: Int64?, isEncrypted: Bool = false) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.isEncrypted = isEncrypted
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case name
        case isDirectory
        case size
        case isEncrypted = "encrypted"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
    }
}
