@testable import FilesClient
import Foundation
import Testing
import TestUtils

struct UploadResumeLinksTests {
    @Test
    func forgettingDropsEverySavedLinkAndNothingElse() throws {
        let suite = TestID.name()
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let link = TusResumeMemory(
            serverURL: TestHost.serverURL, scope: TestAccountID.alice, destination: TestFolder.inbox,
            fileName: TestFile.notes, fingerprint: TestETag.first, defaults: defaults
        )
        link.uploadURL = TestHost.serverURL
        defaults.set(true, forKey: TestFolder.other)

        UploadResumeLinks.forgetAll(in: defaults)

        #expect(link.uploadURL == nil)
        #expect(defaults.bool(forKey: TestFolder.other))
    }
}
