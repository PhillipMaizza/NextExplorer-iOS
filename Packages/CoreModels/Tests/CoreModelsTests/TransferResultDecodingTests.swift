@testable import CoreModels
import Foundation
import Testing

@Suite("TransferResult decoding")
struct TransferResultDecodingTests {
    @Test("decodes the move/copy response body")
    func decodesResponseBody() throws {
        let result = try CoreModelsFixture.transferResultMoveWithSkippedItem.decode(TransferResult.self)
        #expect(result.destination == "Documents/Work")
        #expect(result.items.count == 2)
        #expect(result.items[0].skipped == false)
        #expect(result.items[1].skipped == true)
        #expect(result.movedCount == 1)
        #expect(result.skippedCount == 1)
    }

    @Test("edge case: missing skipped defaults to false")
    func missingSkippedDefaultsFalse() throws {
        let result = try CoreModelsFixture.transferResultMissingSkipped.decode(TransferResult.self)
        #expect(result.items[0].skipped == false)
        #expect(result.movedCount == 1)
        #expect(result.skippedCount == 0)
    }
}
