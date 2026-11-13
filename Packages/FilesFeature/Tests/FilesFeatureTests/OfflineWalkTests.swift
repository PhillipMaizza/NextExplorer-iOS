import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Walking a pinned folder always ends: each folder is listed once, and only what lies below the
/// folder that listed it is kept, whatever the listing answers.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineWalkTests: OfflineDownloadsTestSupport {
    private func walk(_ listings: @escaping @Sendable (String) -> [FileItem]) async throws -> OfflineWalkResult {
        try await OfflineDownloadsFeature.walk(
            roots: [folder("A")],
            serverURL: serverURL,
            filesClient: withDependencies {
                $0.filesClient.browse = { _, path in
                    BrowseResult(items: listings(path), access: BrowseTestSupport.readOnlyAccess, path: path)
                }
            } operation: {
                @Dependency(\.filesClient) var client
                return client
            }
        )
    }

    @Test("A listing that hands back its own folder and its parent ends instead of looping")
    func aLoopingListingEnds() async throws {
        let result = try await walk { path in
            path == "A"
                ? [folder("A"), file(TestFile.aText, path: "A")]
                : [folder("A"), folder("B", path: "A")]
        }

        #expect(result.files.map(\.id) == ["A/\(TestFile.aText)"])
        #expect(!result.hasIncompleteWalk)
    }

    @Test("Items a listing reports outside its folder are not kept with it")
    func itemsOutsideTheFolderAreIgnored() async throws {
        let result = try await walk { path in
            path == "A" ? [file(TestFile.aText, path: "A"), file(TestFile.bText), folder("Elsewhere")] : []
        }

        #expect(result.files.map(\.id) == ["A/\(TestFile.aText)"])
    }

    @Test("A folder reached twice is listed once")
    func aFolderIsListedOnce() async throws {
        let listed = LockIsolated<[String]>([])
        let result = try await walk { path in
            listed.withValue { $0.append(path) }
            return path == "A" ? [folder("B", path: "A"), folder("B", path: "A")] : []
        }

        #expect(listed.value.sorted() == ["A", "A/B"])
        #expect(result.files.isEmpty)
    }
}
