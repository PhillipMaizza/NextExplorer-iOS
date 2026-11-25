import Foundation

public struct FolderSort: Decodable, Equatable, Sendable {
    public let field: String
    public let isAscending: Bool

    public init(field: String, isAscending: Bool) {
        self.field = field
        self.isAscending = isAscending
    }

    public var order: String {
        isAscending ? Order.ascending : Order.descending
    }

    public static func folderKey(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private enum Order {
        static let ascending = "asc"
        static let descending = "desc"
    }

    private enum CodingKeys: String, CodingKey {
        case field = "by"
        case order
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = try container.decode(String.self, forKey: .field).trimmingCharacters(in: .whitespaces)
        let order = try container.decode(String.self, forKey: .order)
        guard !field.isEmpty, order == Order.ascending || order == Order.descending else {
            throw DecodingError.dataCorruptedError(forKey: .order, in: container, debugDescription: "Not a folder sort")
        }
        isAscending = order == Order.ascending
    }
}

struct FolderSorts: Decodable {
    let entries: [String: FolderSort]

    private struct FolderKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FolderKey.self)
        var entries: [String: FolderSort] = [:]
        for key in container.allKeys {
            let path = FolderSort.folderKey(key.stringValue)
            guard !path.isEmpty, let sort = try? container.decode(FolderSort.self, forKey: key) else { continue }
            entries[path] = sort
        }
        self.entries = entries
    }
}
