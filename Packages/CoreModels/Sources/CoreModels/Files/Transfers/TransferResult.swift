/// The body of a successful `POST /api/files/copy` or `POST /api/files/move`, confirmed
/// against `backend/src/services/fileTransferService.js` `transferItems`: `{ success: true,
/// destination, items: [{ from, to, skipped? }] }`. A `skipped` entry is a `move` whose
/// target folder is already the item's parent, which the server treats as a no op.
public struct TransferResult: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let from: String
        public let to: String
        public let isSkipped: Bool

        public init(from: String, to: String, isSkipped: Bool = false) {
            self.from = from
            self.to = to
            self.isSkipped = isSkipped
        }

        private enum CodingKeys: String, CodingKey {
            case from, to
            case isSkipped = "skipped"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = try container.decode(String.self, forKey: .from)
            to = try container.decode(String.self, forKey: .to)
            isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        }
    }

    public let destination: String
    public let items: [Entry]

    public init(destination: String, items: [Entry]) {
        self.destination = destination
        self.items = items
    }

    /// Entries the server actually acted on.
    public var movedCount: Int {
        items.filter { !$0.isSkipped }.count
    }

    public var skippedCount: Int {
        items.filter(\.isSkipped).count
    }
}
