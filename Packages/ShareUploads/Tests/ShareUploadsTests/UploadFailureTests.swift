import Foundation
@testable import ShareUploads
import Testing

@Suite("Upload failures")
struct UploadFailureTests {
    @Test("An HTTP status decides the cause before any transport error")
    func statusCodes() {
        #expect(UploadFailureCause.classify(statusCode: 401, error: nil) == .unauthorized)
        #expect(UploadFailureCause.classify(statusCode: 403, error: nil) == .forbidden)
        #expect(UploadFailureCause.classify(statusCode: 507, error: nil) == .serverFull)
        #expect(UploadFailureCause.classify(statusCode: 413, error: nil) == .serverFull)
        #expect(UploadFailureCause.classify(statusCode: 500, error: nil) == .other)
        #expect(UploadFailureCause.classify(statusCode: 302, error: nil) == .other, "a refused redirect is not a sign in problem")
        #expect(UploadFailureCause.classify(statusCode: 401, error: URLError(.timedOut)) == .unauthorized)
    }

    @Test("Connectivity errors are network failures, other errors are not")
    func transportErrors() {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed] {
            #expect(UploadFailureCause.classify(statusCode: nil, error: URLError(code)) == .network)
        }
        #expect(UploadFailureCause.classify(statusCode: nil, error: URLError(.cancelled)) == .other)
        #expect(UploadFailureCause.classify(statusCode: nil, error: CocoaError(.fileReadUnknown)) == .other)
        #expect(UploadFailureCause.classify(statusCode: nil, error: nil) == .other)
    }

    @Test("A result survives the round trip through its file token")
    func resultTokens() {
        #expect(UploadResult(token: UploadResult.success.token) == .success)
        for cause in UploadFailureCause.allCases {
            #expect(UploadResult(token: UploadResult.failure(cause).token) == .failure(cause))
        }
        #expect(UploadResult(token: "garbage") == nil)
        #expect(UploadResult(token: "") == nil)
    }

    private func response(_ status: Int) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://files.example.com/api/upload"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    @Test("A transport error is a failure even when a response arrived")
    func errorWins() throws {
        let result = try BackgroundUploader.result(response: response(200), body: Data(), error: URLError(.networkConnectionLost))
        #expect(result == .failure(.network))
    }

    @Test("Failing statuses become their causes")
    func failingStatuses() throws {
        #expect(try BackgroundUploader.result(response: response(401), body: Data(), error: nil) == .failure(.unauthorized))
        #expect(try BackgroundUploader.result(response: response(507), body: Data(), error: nil) == .failure(.serverFull))
        #expect(try BackgroundUploader.result(response: response(403), body: Data(), error: nil) == .failure(.forbidden))
    }

    @Test("A 200 with no usable reply is not a success")
    func emptyReply() throws {
        #expect(try BackgroundUploader.result(response: response(200), body: Data(), error: nil) == .failure(.other))
        #expect(try BackgroundUploader.result(response: response(200), body: Data("not json".utf8), error: nil) == .failure(.other))
        #expect(BackgroundUploader.result(response: nil, body: Data(), error: nil) == .failure(.other))
    }

    @Test("A 200 carrying the stored file is a success")
    func storedFileReply() throws {
        let body = Data("""
        [{"name":"a.jpg","path":"Photos","dateModified":"2026-01-01T00:00:00.000Z","size":3,"kind":"jpg","supportsThumbnail":true}]
        """.utf8)
        #expect(try BackgroundUploader.result(response: response(200), body: body, error: nil) == .success)
    }
}
