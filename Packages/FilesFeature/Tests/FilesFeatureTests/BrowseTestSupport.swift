import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Synchronization
import Testing
import TestUtils

/// Fixtures the Browse tab and app shell tests share.
enum BrowseTestSupport {
    static let serverURL: URL = {
        guard let url = URL(string: TestHost.exampleURLString) else {
            preconditionFailure("The test server URL literal is valid")
        }
        return url
    }()

    static let fullAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
    static let readOnlyAccess = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
}

extension DependencyValues {
    /// Every folder answers with an empty read only listing, no favorites exist and the server
    /// reports no features, so a folder load ends after its two responses and starts nothing else.
    mutating func serveEmptyFolders() {
        filesClient.browse = { _, path in BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path) }
        filesClient.favorites = { _ in [] }
        filesClient.serverFeatures = { _ in throw FilesClientError.offline }
    }

    /// Each listed folder answers with an empty read only listing once the test opens its gate, so
    /// reloads of several folders deliver one at a time, in the order the test chooses. Listing a
    /// folder without a gate is a test failure. Favorites and server features answer as in `serveEmptyFolders`.
    mutating func holdFolderListings(_ gates: [String: AsyncGate]) {
        filesClient.browse = { _, path in
            guard let gate = gates[path] else {
                Issue.record("Unexpected listing of \(path)")
                return BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            try await gate.wait()
            return BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path)
        }
        filesClient.favorites = { _ in [] }
        filesClient.serverFeatures = { _ in throw FilesClientError.offline }
    }
}

extension FilesClient {
    func with(_ change: (inout FilesClient) -> Void) -> FilesClient {
        var copy = self
        change(&copy)
        return copy
    }
}

/// Holds every caller of one fake endpoint until the test lets that call through, numbered in the
/// order the calls arrived. Calls that overlap on the same endpoint then answer in an order the
/// test chooses, and `arrival(_:)` tells the test a call is parked before it relies on its number.
final class NumberedCalls: Sendable {
    private let arrivals: [AsyncGate]
    private let releases: [AsyncGate]
    private let counter = Mutex(0)

    init(capacity: Int) {
        arrivals = (0 ..< capacity).map { _ in AsyncGate() }
        releases = (0 ..< capacity).map { _ in AsyncGate() }
    }

    /// Called by the fake: parks until the test releases this call.
    func park() async throws {
        let number = counter.withLock { value in
            defer { value += 1 }
            return value
        }
        arrivals[number].open()
        try await releases[number].wait()
    }

    /// Returns once call `number` is parked.
    func arrival(_ number: Int) async throws {
        try await arrivals[number].wait()
    }

    func release(_ number: Int) {
        releases[number].open()
    }
}
