import Foundation
import Testing
@testable import CoreModels

@Suite("TransferResult decoding")
struct TransferResultDecodingTests {
    @Test("decodes the move/copy response body")
    func decodesResponseBody() throws {
        let json = #"""
        {"success": true, "destination": "Documents/Work", "items": [
            {"from": "Inbox/a.txt", "to": "Documents/Work/a.txt"},
            {"from": "Inbox/b.txt", "to": "Documents/Work/b.txt", "skipped": true}
        ]}
        """#
        let result = try JSONDecoder().decode(TransferResult.self, from: Data(json.utf8))
        #expect(result.destination == "Documents/Work")
        #expect(result.items.count == 2)
        #expect(result.items[0].skipped == false)
        #expect(result.items[1].skipped == true)
        #expect(result.movedCount == 1)
        #expect(result.skippedCount == 1)
    }

    @Test("edge case: missing skipped defaults to false")
    func missingSkippedDefaultsFalse() throws {
        let json = #"{"destination": "A", "items": [{"from": "x", "to": "A/x"}]}"#
        let result = try JSONDecoder().decode(TransferResult.self, from: Data(json.utf8))
        #expect(result.items[0].skipped == false)
        #expect(result.movedCount == 1)
        #expect(result.skippedCount == 0)
    }
}
