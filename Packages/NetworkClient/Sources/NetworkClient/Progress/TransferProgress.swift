import Foundation

/// Bytes moved so far in a streaming transfer, and the total when the server declared one
/// (`Content-Length`). A streamed archive built on the fly has no total, so only the count moves.
public struct TransferProgress: Equatable, Sendable {
    public var receivedBytes: Int64
    public var expectedBytes: Int64?

    public init(receivedBytes: Int64, expectedBytes: Int64?) {
        self.receivedBytes = receivedBytes
        self.expectedBytes = expectedBytes
    }

    /// 0...1 when the total is known.
    public var fraction: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }

    public var isComplete: Bool {
        guard let expectedBytes else { return false }
        return receivedBytes >= expectedBytes
    }
}
