import FilesClient
@testable import FilesFeature
import Localization
import Testing

/// A pinned row says what the run is doing with it: nothing extra when current, a short state otherwise.
struct OfflineSyncStateTests {
    @Test("Each run phase maps to one row state", arguments: [
        (OfflineDownloadProgress.Phase.idle, OfflineSyncState.upToDate),
        (.completed, .upToDate),
        (.preparing, .updating),
        (.downloading, .updating),
        (.waitingForNetwork, .waitingForNetwork),
        (.failed("Disk full"), .failed),
    ])
    func phaseMapsToState(phase: OfflineDownloadProgress.Phase, expected: OfflineSyncState) {
        #expect(OfflineSyncState(phase: phase) == expected)
    }

    @Test("A current row adds no text, every other state names itself")
    func titles() {
        #expect(OfflineSyncState.upToDate.title == nil)
        #expect(OfflineSyncState.updating.title == L10n.Offline.rowUpdating)
        #expect(OfflineSyncState.waitingForNetwork.title == L10n.Offline.rowWaitingForNetwork)
        #expect(OfflineSyncState.failed.title == L10n.Offline.rowUpdateFailed)
    }

    @Test("The failure message does not change what the row says")
    func failureMessageIsIgnored() {
        #expect(OfflineSyncState(phase: .failed("a")) == OfflineSyncState(phase: .failed("b")))
    }
}
