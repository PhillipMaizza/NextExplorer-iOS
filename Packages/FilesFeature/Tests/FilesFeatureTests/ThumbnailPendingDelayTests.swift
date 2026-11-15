@testable import FilesFeature
import Testing

struct ThumbnailPendingDelayTests {
    @Test("Without a request from the server the thumbnail is asked again after two seconds")
    func defaultsToTwoSeconds() {
        #expect(ThumbnailImage.pendingDelay(asked: nil) == .seconds(2))
    }

    @Test("What the server asks for is used when it is reasonable")
    func usesWhatTheServerAsked() {
        #expect(ThumbnailImage.pendingDelay(asked: .milliseconds(1500)) == .milliseconds(1500))
    }

    @Test("A zero or negative wait cannot make the app ask in a tight loop", arguments: [
        Duration.zero, .milliseconds(-1), .seconds(-60),
    ])
    func neverBelowHalfASecond(asked: Duration) {
        #expect(ThumbnailImage.pendingDelay(asked: asked) == .milliseconds(500))
    }

    @Test("A huge wait cannot park the thumbnail for good")
    func neverAboveTenSeconds() {
        #expect(ThumbnailImage.pendingDelay(asked: .seconds(86400)) == .seconds(10))
    }
}
