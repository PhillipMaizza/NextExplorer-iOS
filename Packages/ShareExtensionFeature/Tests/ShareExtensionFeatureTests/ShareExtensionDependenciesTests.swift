import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import NetworkClient
@testable import ShareExtensionFeature
import Testing
import TestUtils

struct ShareExtensionDependenciesTests {
    private let serverURL = URL(string: TestHost.serverURLString) ?? URL(fileURLWithPath: "/")

    private var listingJSON: Data {
        get throws { try ShareExtensionFixture.emptyPhotosListing.data() }
    }

    private var listing: BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(
                canRead: true,
                canWrite: true,
                canUpload: true,
                canDelete: true,
                canShare: true,
                canDownload: true
            ),
            path: TestFolder.photos
        )
    }

    @Test("the extension's directory cache is the no cache store")
    func configureReplacesTheDirectoryCache() {
        withDependencies {
            ShareExtensionDependencies.configure(&$0)
        } operation: {
            @Dependency(\.directoryCacheStore) var store
            store.write(
                serverURL: serverURL,
                path: TestFolder.photos,
                result: listing,
                etag: "\"v1\"",
                fetchedAt: MockClock.now
            )
            #expect(store.read(serverURL: serverURL, path: TestFolder.photos) == nil)
            #expect(store.totalSizeBytes() == 0)
        }
    }

    @Test("browsing from the extension persists no listing, so a second browse sends no validator")
    func browsingNeverPersistsAListing() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let body = try listingJSON
        var network = NetworkClient()
        network.send = { request in
            requests.withValue { $0.append(request) }
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: [HTTPHeaderField.etag: "\"v1\""]
            ))
            return (body, response)
        }
        let capturedNetwork = network
        let filesClient = withDependencies {
            $0.networkClient = capturedNetwork
            ShareExtensionDependencies.configure(&$0)
        } operation: {
            @Dependency(\.filesClient) var client
            return client
        }

        _ = try await filesClient.browse(serverURL, TestFolder.photos)
        _ = try await filesClient.browse(serverURL, TestFolder.photos)

        let validators = requests.value.map { $0.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch) }
        #expect(validators == [nil, nil], "nothing was cached, so nothing is revalidated")
    }
}

private enum MockClock {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}
