@testable import CoreModels
import Foundation
import Testing

@Suite("BrowseResult decoding")
struct BrowseResultDecodingTests {
    @Test("decodes items alongside the access object")
    func decodesItemsAndAccess() throws {
        let result = try CoreModelsFixture.browseResultDirectoryWithAccess.decode(BrowseResult.self)
        #expect(result.items.count == 1)
        #expect(result.access.canRead == true)
        #expect(result.access.canWrite == false)
        #expect(result.path == "Home")
    }

    @Test("edge case: an empty directory decodes with an empty items array")
    func decodesEmptyDirectory() throws {
        let result = try CoreModelsFixture.browseResultEmptyDirectory.decode(BrowseResult.self)
        #expect(result.items.isEmpty)
    }
}
