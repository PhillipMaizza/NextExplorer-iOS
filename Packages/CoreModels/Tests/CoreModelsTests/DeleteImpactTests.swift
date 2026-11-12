@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("DeleteImpact")
struct DeleteImpactTests {
    @Test("only the share count is read, the share rows the server also sends are ignored")
    func decodesCountOnly() throws {
        let impact = try CoreModelsFixture.deleteImpactTwoLinks.decode(DeleteImpact.self)
        #expect(impact == DeleteImpact(shareCount: 2))
    }

    @Test("a response without a count fails to decode so the UI never claims zero links by mistake")
    func missingCountThrows() {
        #expect(throws: DecodingError.self) {
            try CoreModelsFixture.deleteImpactMissingShareCount.decode(DeleteImpact.self)
        }
    }

}
