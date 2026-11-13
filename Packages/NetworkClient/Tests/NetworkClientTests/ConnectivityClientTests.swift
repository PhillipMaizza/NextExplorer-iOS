@testable import NetworkClient
import Testing

@Suite("ConnectivityClient")
struct ConnectivityClientTests {
    @Test(
        "a client built without a metered answer never reports a metered connection, so prefetching is not blocked by default"
    )
    func defaultsToUnmetered() {
        let client = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } })
        #expect(!client.isMetered())
        #expect(!client.isOnline())
    }

    @Test("the test and preview clients assume an unmetered online connection")
    func valueAssumesOnline() {
        for client in [ConnectivityClient.testValue, .previewValue] {
            #expect(client.isOnline())
            #expect(!client.isMetered())
        }
    }
}
