@testable import FilesFeature
import Testing

struct OfflineWaitingForNetworkStateTests {
    @Test
    func waitingForNetworkIsNotAnActiveRunSoPinsAndManageRowsStayVisible() {
        var progress = OfflineDownloadProgress()
        progress.phase = .waitingForNetwork

        #expect(!progress.isActive)
        #expect(progress.fractionComplete == 0)
    }
}
