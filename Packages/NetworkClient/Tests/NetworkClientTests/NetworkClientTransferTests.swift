import Foundation
@testable import NetworkClient
import Testing
import TestUtils

extension NetworkClientLiveTests {
    private var uploadURL: URL {
        URL(string: Constants.uploadURLString) ?? URL(filePath: "/")
    }

    private func withBodyFile(_ body: (URL) async throws -> Void) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("upload-body-\(TestID.name())")
        try Data(Constants.uploadBody.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try await body(file)
    }

    @Test("an upload returns the server's answer and sends the request as a long budget mutation with the given method")
    func uploadReturnsResponse() async throws {
        StubURLProtocol.stub = .init(statusCode: 201, headers: [:], body: Data(Constants.uploadAnswer.utf8))
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        try await withBodyFile { file in
            let (data, response) = try await client.upload(URLRequest(url: uploadURL, method: .put), file) { _ in }
            #expect(response.statusCode == 201)
            #expect(String(decoding: data, as: UTF8.self) == Constants.uploadAnswer)
        }
        #expect(StubURLProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubURLProtocol.lastRequest?.url == uploadURL)
    }

    @Test("an upload failure that is not a timeout maps like any other transport failure")
    func uploadOfflineFailure() async throws {
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        try await withBodyFile { file in
            await #expect(throws: NetworkError.offline) {
                _ = try await client.upload(URLRequest(url: uploadURL, method: .post), file) { _ in }
            }
        }
    }

    @Test("a proxy error page served for a download is a plain response, not a certificate failure")
    func downloadOrdinary400IsNotACertificateFailure() async throws {
        StubURLProtocol.stub = .init(statusCode: 400, headers: [:], body: Data(Constants.badRequestBody.utf8))
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let (file, response) = try await client.download(URLRequest(url: uploadURL))
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(response.statusCode == 400)
        #expect(try String(contentsOf: file, encoding: .utf8) == Constants.badRequestBody)
    }
}

@Suite("NetworkClient non HTTP answers")
struct NetworkClientNonHTTPTests {
    private let url = URL(string: Constants.uploadURLString) ?? URL(filePath: "/")

    @Test("every transfer entry point reports an invalid response when the answer is not HTTP")
    func nonHTTPResponseIsInvalid() async throws {
        let client = NetworkClient.live(protocolClasses: [NonHTTPURLProtocol.self])
        let request = URLRequest(url: url)
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("upload-body-\(TestID.name())")
        try Data(Constants.uploadBody.utf8).write(to: body)
        defer { try? FileManager.default.removeItem(at: body) }

        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.send(request) }
        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.lowPrioritySend(request) }
        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.upload(request, body) { _ in } }
        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.download(request) }
        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.lowPriorityDownload(request) }
        await #expect(throws: NetworkError.invalidResponse) { _ = try await client.downloadWithProgress(request) { _ in } }
    }

    @Test("a non URLError is kept as a transport failure with its own description")
    func nonURLErrorIsTransport() {
        struct Failure: LocalizedError {
            var errorDescription: String? { TestFailure.offline }
        }
        #expect(NetworkError.from(Failure()) == .transport(TestFailure.offline))
    }
}

@Suite("NetworkClient cancellation")
struct NetworkClientCancellationTests {
    @Test("cancelling a download with progress stops the underlying request and fails with a transport error, never hanging")
    func cancelledProgressDownloadStopsTheRequest() async throws {
        let signals = HangingURLProtocol.signals.withLock { $0 }
        let client = NetworkClient.live(protocolClasses: [HangingURLProtocol.self])
        let request = URLRequest(url: URL(string: Constants.uploadURLString) ?? URL(filePath: "/"))

        let transfer = Task {
            try await client.downloadWithProgress(request) { _ in }
        }
        try await signals.started.wait()
        transfer.cancel()
        let result = await transfer.result
        try await signals.stopped.wait()

        guard case let .failure(error) = result, case .transport = error as? NetworkError else {
            Issue.record("expected a transport failure, got \(result)")
            return
        }
    }
}

private enum Constants {
    static let uploadURLString = "https://example.com/api/upload"
    static let uploadBody = "payload"
    static let uploadAnswer = "stored"
    static let badRequestBody = "400 Bad Request"
}
