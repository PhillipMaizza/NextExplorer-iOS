import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Timeout budgets and how timeouts are told apart from being offline, through `FilesClient.live` against a stubbed
/// `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientTimeoutTests: FilesClientLiveHarness {
        @Test
        func aTimedOutMutationSurfacesAsTimedOutNotOffline() async {
            resetStubs()
            StubURLProtocol.failure = URLError(.timedOut)
            let item = FileItem(
                name: TestFile.aText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )

            await #expect(throws: FilesClientError.timedOut) {
                try await makeClient().deleteItems(serverURL, [item])
            }
            resetStubs()
        }

        @Test
        func aTimedOutReadStillSurfacesAsOffline() async {
            resetStubs()
            StubURLProtocol.failure = URLError(.timedOut)

            await #expect(throws: FilesClientError.offline) {
                _ = try await makeClient().browse(serverURL, TestFolder.docs)
            }
            resetStubs()
        }

        @Test
        func theSaveAndVersionDeleteWritesGetTheLongMutationBudgetAndTimeOutAsTimedOut() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            StubURLProtocol.methodStubs["POST /api/versions/delete"] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()

            try await client.saveTextContent(serverURL, TestPath.docsNew, FilesClientTestValue.localEdit)
            try await client.deleteVersions(serverURL, TestPath.docsNew, [TestETag.first], false)
            try await client.deleteVersions(serverURL, TestPath.docsNew, [], true)

            let editorSave = StubURLProtocol.requests
                .first { $0.httpMethod == HTTPMethod.put.rawValue && $0.url?.path == "/api/editor" }
            let deletes = StubURLProtocol.requests.filter { $0.url?.path == "/api/versions/delete" }
            #expect(editorSave?.timeoutInterval == NetworkClient.mutationRequestTimeout)
            #expect(deletes.count == 2)
            #expect(deletes.allSatisfy { $0.timeoutInterval == NetworkClient.mutationRequestTimeout })

            StubURLProtocol.failure = URLError(.timedOut)
            await #expect(throws: FilesClientError.timedOut) {
                try await client.saveTextContent(serverURL, TestPath.docsNew, FilesClientTestValue.localEdit)
            }
            await #expect(throws: FilesClientError.timedOut) {
                try await client.deleteVersions(serverURL, TestPath.docsNew, [], true)
            }
            resetStubs()
        }

        @Test
        func onlyServerSideMutationsGetTheLongBudgetWhileReadsAndPostedReadsKeepTheInteractiveOne() async throws {
            resetStubs()
            let item = FileItem(
                name: "n.txt",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs["DELETE /api/files"] = try editorStub(
                statusCode: 200,
                fixture: .commonEmptyObject
            )
            StubURLProtocol.methodStubs["POST /api/files/move"] = try editorStub(
                statusCode: 200, fixture: .itemMutationTransferToOther
            )
            StubURLProtocol.methodStubs["GET /api/browse/Docs"] = try editorStub(
                statusCode: 200,
                fixture: .browseEmptyDocsWithAccess
            )
            let client = makeClient()

            _ = try await client.fetchTextContent(serverURL, item.id)
            _ = try await client.browse(serverURL, TestFolder.docs)
            try await client.deleteItems(serverURL, [item])
            _ = try await client.transferItems(serverURL, [item], "Other", .move)

            func timeout(_ method: String, _ path: String) -> TimeInterval? {
                StubURLProtocol.requests.first { $0.httpMethod == method && $0.url?.path == path }?.timeoutInterval
            }
            let interactive = URLRequest(url: serverURL).timeoutInterval
            #expect(timeout("POST", "/api/editor") == interactive)
            #expect(timeout("GET", "/api/browse/Docs") == interactive)
            #expect(timeout("DELETE", "/api/files") == NetworkClient.mutationRequestTimeout)
            #expect(timeout("POST", "/api/files/move") == NetworkClient.mutationRequestTimeout)
            resetStubs()
        }

        @Test
        func aStalledDownloadFallsBackToThePinnedOfflineCopyBecauseItIsOfflineNotTimedOut() async throws {
            resetStubs()
            let scope = "offline-fallback-\(TestID.name())"
            defer { OfflineCache.removeScope(scope) }
            let pinned = FileItem(
                name: Constants.binaryName,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: "bin"
            )
            let changedOnServer = FileItem(
                name: Constants.binaryName,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 2,
                kind: "bin"
            )
            let source = FileManager.default.temporaryDirectory.appendingPathComponent("pin-src-\(TestID.name())")
            try Data("x".utf8).write(to: source)
            _ = try OfflineCache.store(downloadedURL: source, item: pinned, scope: scope)
            StubURLProtocol.failure = URLError(.timedOut)
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue,
                activeScope: { scope }
            )

            let url = try await client.downloadRawFile(serverURL, changedOnServer)

            #expect(url == OfflineCache.localURL(forPath: pinned.id, scope: scope))
            resetStubs()
        }

        @Test
        func aTimedOutEditorReadIsOfflineNotATimedOutMutation() async {
            resetStubs()
            StubURLProtocol.failure = URLError(.timedOut)

            await #expect(throws: FilesClientError.offline) {
                _ = try await makeClient().fetchTextContent(serverURL, TestPath.docsNote)
            }
            resetStubs()
        }
    }
}

private enum Constants {
    static let binaryName = "n.bin"
}
