import Foundation
@testable import NetworkClient
import Testing
import TestUtils

@Suite("NetworkClient timeout policy")
struct NetworkClientTimeoutTests {
    private let url = URL(string: "https://example.com/api/files/transfer") ?? URL(filePath: "/")

    @Test
    func aTimedOutMarkedMutationIsNotMappedToOffline() {
        #expect(NetworkError.from(URLError(.timedOut), url: url, isMutation: true) == .timedOut)
    }

    @Test
    func aTimedOutRequestThatIsNotAMutationStaysOffline() {
        #expect(NetworkError.from(URLError(.timedOut), url: url) == .offline)
    }

    @Test
    func otherConnectivityFailuresOnAMutationStayOffline() {
        #expect(NetworkError.from(URLError(.notConnectedToInternet), url: url, isMutation: true) == .offline)
    }

    @Test
    func markingAMutationGivesTheLongBudgetAndNothingElseDoes() {
        let marked = NetworkClient.markingAsMutation(URLRequest(url: url, method: .post))
        let plainPost = URLRequest(url: url, method: .post)

        #expect(marked.timeoutInterval == NetworkClient.mutationRequestTimeout)
        #expect(NetworkClient.isMutation(marked))
        #expect(!NetworkClient.isMutation(plainPost))
        #expect(!NetworkClient.isMutation(URLRequest(url: url, method: .delete)))
        #expect(NetworkClient.mutationRequestTimeout >= 120)
    }

    @Test
    func aLongerCallerTimeoutIsNeverShortened() {
        var request = URLRequest(url: url, method: .post)
        request.timeoutInterval = NetworkClient.mutationRequestTimeout * 2

        #expect(NetworkClient.markingAsMutation(request).timeoutInterval == NetworkClient.mutationRequestTimeout * 2)
    }
}

extension NetworkClientLiveTests {
    private var requestURL: URL {
        URL(string: "https://example.com/api/files/transfer") ?? URL(filePath: "/")
    }

    @Test
    func aPostThatReadsKeepsTheInteractiveBudgetAndMapsATimeoutToOffline() async {
        StubURLProtocol.failure = URLError(.timedOut)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        await #expect(throws: NetworkError.offline) {
            _ = try await client.send(URLRequest(url: requestURL, method: .post))
        }
        #expect(StubURLProtocol.lastRequest?.timeoutInterval == URLRequest(url: requestURL).timeoutInterval)
        #expect(StubURLProtocol.lastRequest.map { !NetworkClient.isMutation($0) } == true)
    }

    @Test
    func aMarkedMutationSendKeepsTheLongBudgetAndMapsATimeoutToTimedOut() async {
        StubURLProtocol.failure = URLError(.timedOut)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        await #expect(throws: NetworkError.timedOut) {
            _ = try await client.send(NetworkClient.markingAsMutation(URLRequest(url: requestURL, method: .post)))
        }
        #expect(StubURLProtocol.lastRequest?.timeoutInterval == NetworkClient.mutationRequestTimeout)
    }

    @Test
    func aStalledPostDownloadMapsToOfflineNotTimedOut() async {
        StubURLProtocol.failure = URLError(.timedOut)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])
        let request = URLRequest(url: requestURL, method: .post)

        await #expect(throws: NetworkError.offline) {
            _ = try await client.download(request)
        }
        await #expect(throws: NetworkError.offline) {
            _ = try await client.downloadWithProgress(request) { _ in }
        }
        await #expect(throws: NetworkError.offline) {
            _ = try await client.lowPriorityDownload(request)
        }
    }

    @Test
    func anUploadAlwaysGetsTheLongBudgetAndATimeoutIsTimedOut() async throws {
        StubURLProtocol.failure = URLError(.timedOut)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("upload-body-\(TestID.name())")
        try Data("x".utf8).write(to: body)
        defer { try? FileManager.default.removeItem(at: body) }

        await #expect(throws: NetworkError.timedOut) {
            _ = try await client.upload(URLRequest(url: requestURL, method: .post), body) { _ in }
        }
        #expect(StubURLProtocol.lastRequest?.timeoutInterval == NetworkClient.mutationRequestTimeout)
    }
}
