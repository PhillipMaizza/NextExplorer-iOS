import FilesClient
import Localization

/// What a pinned item's row says about keeping it current. One sync run covers every pinned item,
/// so the run's phase is the state of each row while it lasts.
enum OfflineSyncState: Equatable {
    case upToDate
    case updating
    case waitingForNetwork
    case failed

    init(phase: OfflineDownloadProgress.Phase) {
        switch phase {
        case .preparing, .downloading: self = .updating
        case .waitingForNetwork: self = .waitingForNetwork
        case .failed: self = .failed
        case .idle, .completed: self = .upToDate
        }
    }

    /// Nil when there is nothing to add to the row.
    var title: String? {
        switch self {
        case .upToDate: nil
        case .updating: L10n.Offline.rowUpdating
        case .waitingForNetwork: L10n.Offline.rowWaitingForNetwork
        case .failed: L10n.Offline.rowUpdateFailed
        }
    }
}
