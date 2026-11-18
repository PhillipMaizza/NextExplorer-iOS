import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The admin Server tools read through `FilesClient.live` against a stubbed `URLSession`.
extension FilesClientLiveTests {
    struct FilesClientCapabilitiesTests: FilesClientLiveHarness {
        @Test
        func capabilitiesAreReadWithTheirVersionsUseAndMissingFormats() async throws {
            try prepare(statusCode: 200, fixture: .capabilitiesMixed)

            let tools = try await makeClient().fetchCapabilities(serverURL)

            try expectRequest(.get, "/api/capabilities")
            #expect(tools.map(\.name) == ["ffmpeg", "ripgrep", "rsync", "7-Zip"])
            #expect(tools[0].isAvailable && tools[0].version == "7.1")
            #expect(!tools[1].isAvailable && tools[1].version == nil)
            #expect(!tools[2].isUsed)
            #expect(tools[3].missingFormats == ["rar"] && tools[3].installPackage == "7zip")
        }

        @Test
        func aNonAdminIsRefused() async throws {
            try prepare(statusCode: 403, fixture: .commonEmptyObject)

            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().fetchCapabilities(serverURL)
            }
        }
    }
}
