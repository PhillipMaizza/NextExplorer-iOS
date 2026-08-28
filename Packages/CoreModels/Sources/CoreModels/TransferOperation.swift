/// Whether a batch of items is being duplicated into a new location or relocated there,
/// mirroring the two backend routes `POST /api/files/copy` and `POST /api/files/move`
/// (`backend/src/routes/files/transfer.js`).
public enum TransferOperation: String, Codable, Equatable, Sendable, CaseIterable {
    case copy
    case move
}
