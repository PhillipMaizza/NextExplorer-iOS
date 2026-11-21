import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Resumable uploads through `FilesClient.live` against a stubbed `URLSession`.
extension FilesClientLiveTests {
    struct FilesClientTusUploadTests: FilesClientLiveHarness {
        private let tusPath = "/api/upload/tus"
        private let uploadPath = "/api/upload/tus/abc123"

        private func makeTempFile(contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name())-tus.bin")
            try Data(contents.utf8).write(to: url)
            return url
        }

        private func tusStub(_ status: Int, headers: [String: String] = [:], body: String = "") -> StubURLProtocol
            .Stub
        {
            .init(statusCode: status, headers: headers, body: Data(body.utf8))
        }

        private func stubForcedChunking() throws {
            let settings = try FilesClientFixture.systemSettingsUploadsChunked.data()
            StubURLProtocol.methodStubs["GET /api/settings"] = .init(
                statusCode: 200, headers: [HTTPHeaderField.contentType: MIMEType.json], body: settings
            )
            StubURLProtocol.methodStubs["POST \(tusPath)"] = tusStub(
                201, headers: [TusUpload.Header.location: "\(TestHost.exampleURLString)\(uploadPath)"]
            )
        }

        @Test
        func metadataCarriesTheNameDestinationAndRelativePathAsBase64() {
            let metadata = TusUpload.metadata(fileName: "a b.txt", destination: "Inbox")
            let expected = [
                "filename \(Data("a b.txt".utf8).base64EncodedString())",
                "uploadTo \(Data("Inbox".utf8).base64EncodedString())",
                "relativePath \(Data("a b.txt".utf8).base64EncodedString())",
            ].joined(separator: ",")
            #expect(metadata == expected)
        }

        @Test
        func theLocationHeaderOnlyContributesItsIdentifier() {
            let own = TusUpload.uploadURL(serverURL: serverURL, location: "https://evil.example/api/upload/tus/abc123")
            #expect(own?.host == serverURL.host)
            #expect(own?.path == uploadPath)
            #expect(TusUpload.uploadURL(serverURL: serverURL, location: "/api/upload/tus/a?b=c") == nil)
            #expect(TusUpload.uploadURL(serverURL: serverURL, location: nil) == nil)
        }

        @Test
        func forcedChunkingSendsEachPieceFromTheServerOffset() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodSequences["PATCH \(uploadPath)"] = [
                tusStub(204, headers: [TusUpload.Header.uploadOffset: "6"]),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: "10"]),
            ]
            let fileURL = try makeTempFile(contents: "0123456789")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            // Straight to the service so the chunk size can be a few bytes.
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 6
            ) { _ in }

            let sent = StubURLProtocol.requests
            #expect(sent.map(\.httpMethod) == ["POST", "PATCH", "PATCH"])
            #expect(sent[1].value(forHTTPHeaderField: TusUpload.Header.uploadOffset) == "0")
            #expect(sent[2].value(forHTTPHeaderField: TusUpload.Header.uploadOffset) == "6")
            #expect(sent.allSatisfy { $0.url?.host == serverURL.host })
        }

        @Test
        func aFailedPieceResumesFromTheOffsetTheServerReports() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodSequences["PATCH \(uploadPath)"] = [
                tusStub(503),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: "4"]),
            ]
            StubURLProtocol.methodStubs["HEAD \(uploadPath)"] = tusStub(
                200, headers: [TusUpload.Header.uploadOffset: "0"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 4
            ) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "HEAD", "PATCH"])
        }

        @Test
        func aFinalizeFailureIsReportedAndNeverRetried() async throws {
            resetStubs()
            try stubForcedChunking()
            let reason = "The file was received, but it could not be put in its folder: the volume is read-only."
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                500,
                headers: [TusUpload.Header.finalizeError: reason.addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics
                ) ?? reason]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            await #expect(throws: FilesClientError.serverMessage(statusCode: 500, message: reason)) {
                try await service.uploadChunked(
                    serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                    destination: TestFolder.inbox, chunkSizeBytes: 4
                ) { _ in }
            }
            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH"])
        }

        @Test
        func anUploadTheServerForgotIsStartedOnceMore() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodSequences["PATCH \(uploadPath)"] = [
                tusStub(404),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: "4"]),
            ]
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 4
            ) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "POST", "PATCH"])
        }

        @Test
        func anEmptyFileCompletesWithTheCreateRequestAlone() async throws {
            resetStubs()
            try stubForcedChunking()
            let fileURL = try makeTempFile(contents: "")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 4
            ) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST"])
            #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: TusUpload.Header.uploadLength) == "0")
        }

        @Test
        func aRefusedDirectUploadFallsBackToChunksAndRemembersTheSize() async throws {
            resetStubs()
            let memory = UploadFallbackMemory(serverURL: serverURL)
            memory.mebibytes = nil
            defer { memory.mebibytes = nil }
            StubURLProtocol.methodStubs["POST /api/upload"] = try tusStub(
                413,
                body: FilesClientFixture.uploadErrorTooLarge.string()
            )
            StubURLProtocol.methodStubs["GET /api/settings"] = try .init(
                statusCode: 200,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: FilesClientFixture.systemSettingsUploadsAutoFallback.data()
            )
            StubURLProtocol.methodStubs["POST \(tusPath)"] = tusStub(
                201, headers: [TusUpload.Header.location: uploadPath]
            )
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                204, headers: [TusUpload.Header.uploadOffset: "4"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["GET", "POST", "GET", "POST", "PATCH"])
            #expect(memory.mebibytes == 96)
        }

        @Test
        func aRefusedDirectUploadStaysAnErrorWhenAutoFallbackIsOff() async throws {
            resetStubs()
            StubURLProtocol.methodStubs["POST /api/upload"] = try tusStub(
                413,
                body: FilesClientFixture.uploadErrorTooLarge.string()
            )
            StubURLProtocol.methodStubs["GET /api/settings"] = try .init(
                statusCode: 200, headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: FilesClientFixture.commonEmptyObject.data()
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            await #expect(throws: FilesClientError.serverMessage(statusCode: 413, message: "too big")) {
                try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }
            }
        }

        private func makeSparseFile(bytes: Int) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name())-big.bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(bytes))
            try handle.close()
            return url
        }

        @Test
        func aPlainTextServerErrorIsRetriedFromTheReportedOffset() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodSequences["PATCH \(uploadPath)"] = [
                tusStub(503, body: "Service Unavailable\n"),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: "4"]),
            ]
            StubURLProtocol.methodStubs["HEAD \(uploadPath)"] = tusStub(
                200, headers: [TusUpload.Header.uploadOffset: "0"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 4
            ) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "HEAD", "PATCH"])
        }

        @Test
        func retriesStopAfterThreeFailuresAndStorageFullIsNeverRetried() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(502)
            StubURLProtocol.methodStubs["HEAD \(uploadPath)"] = tusStub(
                200, headers: [TusUpload.Header.uploadOffset: "0"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            await #expect(throws: FilesClientError.server(statusCode: 502)) {
                try await service.uploadChunked(
                    serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                    destination: TestFolder.inbox, chunkSizeBytes: 4
                ) { _ in }
            }
            #expect(StubURLProtocol.requests.filter { $0.httpMethod == "PATCH" }.count == 4)

            StubURLProtocol.requests = []
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(507)
            await #expect(throws: FilesClientError.server(statusCode: 507)) {
                try await service.uploadChunked(
                    serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                    destination: TestFolder.inbox, chunkSizeBytes: 4
                ) { _ in }
            }
            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH"])
        }

        @Test
        func anUploadForgottenTwiceFails() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(404)
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            await #expect(throws: FilesClientError.server(statusCode: 404)) {
                try await service.uploadChunked(
                    serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                    destination: TestFolder.inbox, chunkSizeBytes: 4
                ) { _ in }
            }
            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "POST", "PATCH"])
        }

        @Test
        func aLargeFileGoesAsPiecesWhenTheAdminForcedChunking() async throws {
            resetStubs()
            try stubForcedChunking()
            let size = UploadMode.largeFileBytes + 1
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                204, headers: [TusUpload.Header.uploadOffset: String(size)]
            )
            let fileURL = try makeSparseFile(bytes: size)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
            #expect(StubURLProtocol.requests[1].url?.path == tusPath)
        }

        @Test
        func aRememberedChunkSizeRoutesTheNextLargeFileToPieces() async throws {
            resetStubs()
            let memory = UploadFallbackMemory(serverURL: serverURL)
            memory.mebibytes = 16
            defer { memory.mebibytes = nil }
            StubURLProtocol.methodStubs["GET /api/settings"] = try .init(
                statusCode: 200,
                headers: [HTTPHeaderField.contentType: MIMEType.json],
                body: FilesClientFixture.systemSettingsUploadsAutoFallback.data()
            )
            StubURLProtocol.methodStubs["POST \(tusPath)"] = tusStub(
                201, headers: [TusUpload.Header.location: uploadPath]
            )
            let size = UploadMode.largeFileBytes + 1
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                204, headers: [TusUpload.Header.uploadOffset: String(size)]
            )
            let fileURL = try makeSparseFile(bytes: size)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        }

        @Test
        func aSmallFileGoesAsPiecesWhenTheAdminForcedChunking() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                204, headers: [TusUpload.Header.uploadOffset: "4"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        }

        @Test
        func anUploadCutOffByAnEndedProcessResumesFromTheServerOffset() async throws {
            resetStubs()
            StubURLProtocol.methodStubs["HEAD \(uploadPath)"] = tusStub(
                200, headers: [TusUpload.Header.uploadOffset: "2"]
            )
            StubURLProtocol.methodStubs["PATCH \(uploadPath)"] = tusStub(
                204, headers: [TusUpload.Header.uploadOffset: "4"]
            )
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))
            let resume = try TusResumeMemory(
                serverURL: serverURL, scope: service.activeScope(), destination: TestFolder.inbox,
                fileName: TestFile.notes, fingerprint: TusResumeMemory.fingerprint(of: fileURL, size: 4)
            )
            resume.uploadURL = TusUpload.uploadURL(serverURL: serverURL, location: uploadPath)
            defer { resume.uploadURL = nil }

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 4
            ) { _ in }

            let sent = StubURLProtocol.requests
            #expect(sent.map(\.httpMethod) == ["HEAD", "PATCH"])
            #expect(sent[1].value(forHTTPHeaderField: TusUpload.Header.uploadOffset) == "2")
            #expect(resume.uploadURL == nil)
        }

        @Test
        func aPieceRefusedForItsSizeIsSentAgainSmaller() async throws {
            resetStubs()
            try stubForcedChunking()
            let size = UploadMode.largeFileBytes + 1
            StubURLProtocol.methodSequences["PATCH \(uploadPath)"] = [
                tusStub(413),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: String(UploadMode.largeFileBytes)]),
                tusStub(204, headers: [TusUpload.Header.uploadOffset: String(size)]),
            ]
            let fileURL = try makeSparseFile(bytes: size)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))

            try await service.uploadChunked(
                serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                destination: TestFolder.inbox, chunkSizeBytes: 16 * UploadSettings.bytesPerMiB
            ) { _ in }

            let offsets = StubURLProtocol.requests.filter { $0.httpMethod == "PATCH" }
                .map { $0.value(forHTTPHeaderField: TusUpload.Header.uploadOffset) }
            #expect(offsets == ["0", "0", String(UploadMode.largeFileBytes)])
        }

        @Test
        func cancellingAnUploadAsksTheServerToDropIt() async throws {
            resetStubs()
            try stubForcedChunking()
            StubURLProtocol.heldMethodKeys = ["PATCH \(uploadPath)"]
            StubURLProtocol.methodStubs["DELETE \(uploadPath)"] = tusStub(204)
            let fileURL = try makeTempFile(contents: "abcd")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let service = FilesService(networkClient: .live(protocolClasses: [StubURLProtocol.self]))
            let upload = Task {
                try await service.uploadChunked(
                    serverURL: serverURL, fileURL: fileURL, fileName: TestFile.notes,
                    destination: TestFolder.inbox, chunkSizeBytes: 4
                ) { _ in }
            }

            while !StubURLProtocol.requests.contains(where: { $0.httpMethod == "PATCH" }) {
                await Task.yield()
            }
            upload.cancel()
            _ = await upload.result
            while !StubURLProtocol.requests.contains(where: { $0.httpMethod == "DELETE" }) {
                await Task.yield()
            }

            #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "DELETE"])
        }
    }
}
