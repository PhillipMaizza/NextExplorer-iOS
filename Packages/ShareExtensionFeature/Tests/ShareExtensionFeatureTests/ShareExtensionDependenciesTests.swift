import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import NetworkClient
@testable import ShareExtensionFeature
import Testing

struct ShareExtensionDependenciesTests {
    private let serverURL = URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/")

    private let listingJSON = Data(#"""
    {"items":[],
     "access":{"canRead":true,"canWrite":true,"canUpload":true,"canDelete":true,"canShare":true,"canDownload":true},
     "path":"Photos"}
    """#.utf8)

    private var listing: BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true),
            path: "Photos"
        )
    }

    @Test("the no cache store never returns what was written to it")
    func noCacheNeverReturnsAWrite() {
        let store = DirectoryCacheStore.noCache
        store.write(serverURL: serverURL, path: "Photos", result: listing, etag: "\"v1\"", fetchedAt: MockClock.now)

        #expect(store.read(serverURL: serverURL, path: "Photos") == nil)
        #expect(store.lastWrittenAt(serverURL: serverURL, path: "Photos") == nil)
        #expect(store.totalSizeBytes() == 0)
    }

    @Test("the extension's directory cache is the no cache store")
    func configureReplacesTheDirectoryCache() {
        withDependencies {
            ShareExtensionDependencies.configure(&$0)
        } operation: {
            @Dependency(\.directoryCacheStore) var store
            store.write(serverURL: serverURL, path: "Photos", result: listing, etag: "\"v1\"", fetchedAt: MockClock.now)
            #expect(store.read(serverURL: serverURL, path: "Photos") == nil)
            #expect(store.totalSizeBytes() == 0)
        }
    }

    @Test("browsing from the extension persists no listing, so a second browse sends no validator")
    func browsingNeverPersistsAListing() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let body = listingJSON
        var network = NetworkClient()
        network.send = { request in
            requests.withValue { $0.append(request) }
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"v1\""]
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

        _ = try await filesClient.browse(serverURL, "Photos")
        _ = try await filesClient.browse(serverURL, "Photos")

        let validators = requests.value.map { $0.value(forHTTPHeaderField: "If-None-Match") }
        #expect(validators == [nil, nil], "nothing was cached, so nothing is revalidated")
    }
}

private enum MockClock {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}
