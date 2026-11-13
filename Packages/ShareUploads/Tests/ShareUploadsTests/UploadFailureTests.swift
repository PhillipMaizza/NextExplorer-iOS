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
        #expect(
            UploadFailureCause.classify(statusCode: 302, error: nil) == .other,
            "a refused redirect is not a sign in problem"
        )
        #expect(UploadFailureCause.classify(statusCode: 401, error: URLError(.timedOut)) == .unauthorized)
    }

    @Test("Connectivity errors are network failures, other errors are not")
    func transportErrors() {
        for code in [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .dnsLookupFailed,
        ] {
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
        let result = try BackgroundUploader.result(response: response(200), error: URLError(.networkConnectionLost))
        #expect(result == .failure(.network))
    }

    @Test(
        "Any 2xx is a success, whatever the reply body says: a retry must never upload the file twice",
        arguments: [200, 201, 204, 299]
    )
    func anyTwoHundredIsASuccess(status: Int) throws {
        #expect(try BackgroundUploader.result(response: response(status), error: nil) == .success)
    }

    @Test("Statuses outside 2xx and a missing response are failures", arguments: [199, 300, 302, 404, 500])
    func otherStatusesFail(status: Int) throws {
        #expect(try BackgroundUploader.result(response: response(status), error: nil) == .failure(.other))
    }

    @Test("No response at all is a failure")
    func noResponse() {
        #expect(BackgroundUploader.result(response: nil, error: nil) == .failure(.other))
    }
}
