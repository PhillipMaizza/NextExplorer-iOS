import ComposableArchitecture
import CoreModels
import Localization

struct SearchLane: Identifiable {
    let title: String
    let sections: SearchResultSections
    var phase: DataPhase = .loaded
    var onShowMore: (() -> Void)?
    var onRetry: (() -> Void)?

    var id: String {
        title
    }

    var rows: [SearchResultItem] {
        sections.onDevice + sections.remote
    }

    var isShown: Bool {
        !rows.isEmpty || phase != .loaded
    }
}

extension BrowseFeature.State {
    func searchLanes(send: @escaping (BrowseFeature.Action) -> Void) -> [SearchLane] {
        guard isSearchingMyFilesAndVolumes else { return [] }
        return [
            SearchLane(
                title: L10n.Browse.myFiles,
                sections: searchResultSections,
                onShowMore: canShowMoreSearchResults && searchPhase != .loading
                    ? { send(.searchShowMoreTapped) }
                    : nil
            ),
            SearchLane(
                title: L10n.Search.volumes,
                sections: volumeResultSections,
                phase: volumeSearch.phase == .idle ? .loaded : volumeSearch.phase,
                onShowMore: volumeSearch.canShowMore ? { send(.searchVolumesShowMoreTapped) } : nil,
                onRetry: { send(.searchRetryTapped) }
            ),
        ]
    }
}

extension StoreOf<BrowseFeature> {
    var searchLanes: [SearchLane] {
        state.searchLanes { [self] in send($0) }
    }
}
