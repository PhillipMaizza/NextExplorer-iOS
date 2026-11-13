import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Editor ETag conflict detection (HEAD preflight, overwrite, ETag bookkeeping) through `FilesClient.live` against a
/// stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientEditorConflictTests: FilesClientLiveHarness {
        @Test
        func savingAnUnchangedFileRevalidatesWithTheOpenETagThenWrites() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v2""#,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()

            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)
            try await client.saveTextContent(serverURL, TestPath.docsNote, "new")
            try await client.saveTextContent(serverURL, TestPath.docsNote, "newer")

            let checks = StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.head.rawValue }
            #expect(checks.map { $0.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch) } == [
                #"W/"v1""#,
                #"W/"v2""#,
            ])
            #expect(checks.first?.url?.query == "path=Docs/n.txt")
            #expect(StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.put.rawValue }.count == 2)
            resetStubs()
        }

        @Test
        func savingAFileChangedOnTheServerThrowsOnceThenOverwrites() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"other""#,
                fixture: .editorContentTheirs
            )
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            await #expect(throws: FilesClientError.changedOnServer) {
                try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            }
            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.put.rawValue })

            try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            #expect(StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.put.rawValue }.count == 1)
            resetStubs()
        }

        @Test
        func aFileDeletedOrRenamedOnTheServerIsAConflictThenOverwrites() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 404)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            await #expect(throws: FilesClientError.changedOnServer) {
                try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            }
            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.put.rawValue })

            try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            #expect(StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.put.rawValue }.count == 1)
            resetStubs()
        }

        @Test(arguments: [400, 413, 415, 422])
        func aClientErrorOnTheHeadPreflightIsInconclusiveSoItPromptsInsteadOfOverwriting(status: Int) async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: status)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            await #expect(throws: FilesClientError.changedOnServer) {
                try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            }
            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.put.rawValue })
            resetStubs()
        }

        @Test
        func aSessionExpiredOnTheHeadPreflightSurfacesAsSessionExpiredNotAConflict() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 401)
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            await #expect(throws: FilesClientError.sessionExpired) {
                try await client.saveTextContent(serverURL, TestPath.docsNote, FilesClientTestValue.localEdit)
            }
            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.put.rawValue })
            resetStubs()
        }

        @Test
        func aNewFileWithNoKnownETagIsSavedWithoutAPreflight() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )

            try await makeClient().saveTextContent(serverURL, TestPath.docsNew, FilesClientTestValue.localEdit)

            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.head.rawValue })
            #expect(StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.put.rawValue }.count == 1)
            resetStubs()
        }

        @Test
        func theConflictCheckIsAHeadRequestSoTheBodyIsNeverDownloaded() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            try await client.saveTextContent(serverURL, TestPath.docsNote, "new")

            #expect(!StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.get.rawValue })
            #expect(StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.head.rawValue })
            resetStubs()
        }

        @Test
        func theBackendETagFormatIsReplayedVerbatimInIfNoneMatch() async throws {
            let backendETag = #"W/"1a2b-3c-lq9z8a1b2c3-lq9z8a9z8y7-t2""#
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: backendETag,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                etag: backendETag,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            try await client.saveTextContent(serverURL, TestPath.docsNote, "new")

            let head = StubURLProtocol.requests.first { $0.httpMethod == HTTPMethod.head.rawValue }
            #expect(head?.value(forHTTPHeaderField: HTTPHeaderField.ifNoneMatch) == backendETag)
            resetStubs()
        }

        @Test
        func theConflictCheckPercentEncodesPlusAmpersandHashPercentAndSpace() async throws {
            resetStubs()
            let path = "Docs/a+b & c#d%e.txt"
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, path)

            try await client.saveTextContent(serverURL, path, "new")

            let head = StubURLProtocol.requests.first { $0.httpMethod == HTTPMethod.head.rawValue }
            #expect(head?.url?.query == "path=Docs/a%2Bb%20%26%20c%23d%25e.txt")
            resetStubs()
        }

        @Test
        func aSaveWithoutAnETagInTheAnswerLeavesTheNextSaveUnchecked() async throws {
            resetStubs()
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
            StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                statusCode: 200,
                fixture: .commonSuccessTrue
            )
            let client = makeClient()
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            try await client.saveTextContent(serverURL, TestPath.docsNote, "one")
            try await client.saveTextContent(serverURL, TestPath.docsNote, "two")

            #expect(StubURLProtocol.requests.filter { $0.httpMethod == HTTPMethod.head.rawValue }.count == 1)
            resetStubs()
        }

        @Test
        func renamingMovingOrDeletingForgetsTheStoredETag() async throws {
            let item = FileItem(
                name: "n.txt",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let serverURL = serverURL
            let cases: [(String, @Sendable (FilesClient) async throws -> Void)] = [
                ("rename", { _ = try await $0.renameItem(serverURL, item, "m.txt") }),
                ("move", { _ = try await $0.transferItems(serverURL, [item], "Other", .move) }),
                ("delete", { try await $0.deleteItems(serverURL, [item]) }),
            ]
            for (name, operation) in cases {
                resetStubs()
                StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                    statusCode: 200,
                    etag: #"W/"v1""#,
                    fixture: .editorContentHi
                )
                StubURLProtocol.methodStubs["POST /api/files/rename"] = try editorStub(
                    statusCode: 200,
                    fixture: .itemMutationRenameMTxt
                )
                StubURLProtocol.methodStubs["POST /api/files/move"] = try editorStub(
                    statusCode: 200,
                    fixture: .itemMutationTransferToOther
                )
                StubURLProtocol.methodStubs["DELETE /api/files"] = try editorStub(
                    statusCode: 200,
                    fixture: .commonEmptyObject
                )
                StubURLProtocol.methodStubs[Constants.headEditor] = try editorStub(statusCode: 304)
                StubURLProtocol.methodStubs[FilesClientTestValue.putEditor] = try editorStub(
                    statusCode: 200,
                    fixture: .commonSuccessTrue
                )
                let client = makeClient()
                _ = try await client.fetchTextContent(serverURL, item.id)

                try await operation(client)
                try await client.saveTextContent(serverURL, item.id, "x")

                #expect(
                    !StubURLProtocol.requests.contains { $0.httpMethod == HTTPMethod.head.rawValue },
                    "\(name) must drop the stored ETag"
                )
            }
            resetStubs()
        }

        @Test
        func editorETagsAreFiledUnderTheScopeTheOperationStartedIn() async throws {
            resetStubs()
            let store = TextEditorETagStore()
            let scopeBox = ScopeBox("scope-a")
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue,
                textEditorETags: store,
                activeScope: { scopeBox.value }
            )
            StubURLProtocol.methodStubs[FilesClientTestValue.postEditor] = try editorStub(
                statusCode: 200,
                etag: #"W/"v1""#,
                fixture: .editorContentHi
            )
            _ = try await client.fetchTextContent(serverURL, TestPath.docsNote)

            let keyA = TextEditorETagStore.key(scope: "scope-a", serverURL: serverURL, path: TestPath.docsNote)
            let keyB = TextEditorETagStore.key(scope: "scope-b", serverURL: serverURL, path: TestPath.docsNote)
            #expect(store.etag(for: keyA) == #"W/"v1""#)
            #expect(store.etag(for: keyB) == nil)
            store.clear(scope: "scope-a")
            #expect(store.etag(for: keyA) == nil)
            resetStubs()
        }
    }
}

private final class ScopeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var scope: String

    init(_ scope: String) {
        self.scope = scope
    }

    var value: String {
        get { lock.withLock { scope } }
        set { lock.withLock { scope = newValue } }
    }
}

private enum Constants {
    static let headEditor = "HEAD /api/editor"
}
