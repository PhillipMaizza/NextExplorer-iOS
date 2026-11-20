import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils

@Suite("A manifest from the App Group is untrusted")
struct ManifestTrustTests {
    private enum Constants {
        static let escapingEnvelope = "../../Library/Cookies/Cookies.binarycookies"
    }

    @Test("Uploads go to the account's own server, whatever the manifest says")
    func cookieFollowsTheAccountServer() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var batch = try harness.makeBatch()
        batch.manifest.serverURL = try #require(URL(string: TestHost.otherServerURLString))

        let specs = BackgroundUploader.taskSpecs(
            for: [0],
            of: batch.manifest,
            in: batch.directory,
            credentials: Harness.credentials
        )

        #expect(specs.first?.request.url?.host == Harness.credentials.serverBaseURL.host)
    }

    @Test("A manifest whose envelope leaves the batch folder is ignored")
    func escapingEnvelopeIsRejected() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var batch = try harness.makeBatch()
        batch.manifest.envelopes[0] = Constants.escapingEnvelope
        try batch.manifest.save(in: batch.directory)

        #expect(Manifest.load(from: batch.directory) == nil)
        #expect(harness.uploader.retryFailed(batchID: batch.id, credentials: Harness.credentials) == 0)
    }

    @Test("A manifest whose lists do not line up is ignored instead of crashing")
    func mismatchedListsAreRejected() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var batch = try harness.makeBatch()
        batch.manifest.contentTypes.removeLast()
        try batch.manifest.save(in: batch.directory)

        #expect(Manifest.load(from: batch.directory) == nil)
    }

    @Test("A manifest the app wrote itself still loads")
    func wellFormedManifestLoads() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let batch = try harness.makeBatch()

        #expect(Manifest.load(from: batch.directory) == batch.manifest)
    }
}
