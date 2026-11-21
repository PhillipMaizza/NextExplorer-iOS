import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import Localization
import SwiftUI

extension BrowseFeature.State {
    /// A folder on an example server holding `items`, for previews.
    static func preview(
        directoryPath: String = "Documents",
        items: [FileItem] = [],
        mutate: (inout Self) -> Void = { _ in }
    ) -> Self {
        var state = Self(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            directoryPath: directoryPath,
            title: L10n.Browse.navigationTitle
        )
        state.items = IdentifiedArray(uniqueElements: items)
        state.phase = items.isEmpty ? .idle : .loaded
        mutate(&state)
        return state
    }
}

@MainActor
private func browsePreview(
    directoryPath: String = "Documents",
    configureClient: (inout FilesClient) -> Void = { _ in },
    mutateState: (inout BrowseFeature.State) -> Void = { _ in }
) -> some View {
    var state = BrowseFeature.State.preview(directoryPath: directoryPath)
    mutateState(&state)
    var client = FilesClient.previewValue
    configureClient(&client)
    let store = Store(initialState: state) {
        BrowseFeature()
    } withDependencies: {
        $0.filesClient = client
    }
    return NavigationStack {
        BrowseContentView(store: store)
            .navigationTitle(L10n.Browse.navigationTitle)
    }
}

let browsePreviewItems: [FileItem] = [
    FileItem(name: "Projects", path: "Documents", dateModified: Date(), size: 0, kind: "directory"),
    FileItem(name: "budget.xlsx", path: "Documents", dateModified: Date(), size: 44_000, kind: "xlsx"),
    FileItem(name: "notes.txt", path: "Documents", dateModified: Date(), size: 1_200, kind: "txt"),
    FileItem(
        name: "cover.jpg",
        path: "Documents",
        dateModified: Date(),
        size: 2_400_000,
        kind: "jpg",
        supportsThumbnail: true
    ),
]

private let browsePreviewEmptyAccess = FileAccess(
    canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
)

#Preview("Browse: content") {
    browsePreview(mutateState: { $0.items = IdentifiedArray(uniqueElements: browsePreviewItems) })
}

#Preview("Browse: loading") {
    browsePreview(mutateState: { $0.phase = .loading })
}

#Preview("Browse: empty folder") {
    browsePreview(
        configureClient: { $0.browse = { _, path in
            BrowseResult(items: [], access: browsePreviewEmptyAccess, path: path)
        } }
    )
}

#Preview("Browse: error") {
    browsePreview(mutateState: { $0.phase = .failed(L10n.EmptyState.loadFailed) })
}

#Preview("Browse: no search results") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
    })
}

#Preview("Browse: searching everywhere") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchScope = .everywhere
        $0.searchPhase = .loading
    })
}

#Preview("Browse: search failed") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
        $0.searchPhase = .failed(L10n.Browse.searchFailed)
    })
}

#Preview("Browse: delete alert, linked shares") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
    })
}

#Preview("Browse: delete alert, share check unavailable") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .unavailable
    })
}
