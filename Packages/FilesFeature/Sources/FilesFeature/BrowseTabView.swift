import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum Constants {
    static let breadcrumbContentSpacing: CGFloat = .space8
}

struct BrowseTabView: View {
    @Bindable var store: StoreOf<BrowseTabFeature>

    /// The topmost screen's path — one `BrowseBreadcrumbBar` instance living here, above the
    /// whole `NavigationStack`, rather than one recreated inside every pushed `BrowseContentView`
    /// (the previous approach): each push used to remount a fresh breadcrumb bar from scratch,
    /// losing its scroll position and any transition between two navigation depths. This one
    /// persists across the whole tab and just updates as `path` changes.
    private var currentDirectoryPath: String {
        store.path.last?.directoryPath ?? store.root.directoryPath
    }

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            BrowseContentView(store: store.scope(state: \.root, action: \.root))
                .navigationTitle(store.root.title)
        } destination: { store in
            BrowseContentView(store: store)
                .navigationTitle(store.title)
        }
        .safeAreaInset(edge: .bottom, spacing: Constants.breadcrumbContentSpacing) {
            if !currentDirectoryPath.isEmpty {
                BrowseBreadcrumbBar(directoryPath: currentDirectoryPath) { path, title in
                    store.send(.navigateToDirectory(path: path, title: title))
                }
            }
        }
        .tint(Color.accent)
    }
}

#Preview {
    BrowseTabView(
        store: Store(
            initialState: BrowseTabFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
