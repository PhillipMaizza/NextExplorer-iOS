import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

extension MainTabFeature.State {
    /// The folder the split view detail's path bar names: the top screen of Browse or of a
    /// favorite. `nil` hides the bar: at a tab's root, in select mode (its toolbar takes the
    /// bottom), and on tabs without folders.
    var splitBreadcrumbPath: String? {
        let directoryPath: String
        let isSelecting: Bool
        switch selectedTab {
        case .browse:
            directoryPath = browse.currentDirectoryPath
            isSelecting = browse.path.last?.isSelecting ?? browse.root.isSelecting
        case .favorites:
            directoryPath = favorites.path.last?.directoryPath ?? ""
            isSelecting = favorites.path.last?.isSelecting ?? false
        case .shared, .downloads, .settings, .trash:
            return nil
        }
        return directoryPath.isEmpty || isSelecting ? nil : directoryPath
    }
}

/// The folder path along the bottom of the split view detail (iPad, an open iPhone Duo, the Mac
/// grid). It floats over the whole split view, sized to the detail column, rather than living in
/// the detail: an overlay on the detail's `NavigationStack` never renders on iOS 27, and a bar
/// carried by each screen slides away with every push instead of staying put.
struct SplitDetailBreadcrumb: View {
    let store: StoreOf<MainTabFeature>
    @AppStorage(AppStorageKeys.browseViewMode) private var browseViewModeRaw = FileListViewMode.list.rawValue

    private var directoryPath: String? {
        guard BrowseBreadcrumbBarMetrics.isShown(browseViewModeRaw: browseViewModeRaw, isSplitViewDetail: true) else {
            return nil
        }
        return store.splitBreadcrumbPath
    }

    var body: some View {
        ZStack {
            if let directoryPath {
                bar(for: directoryPath)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The same step as the tab bar it stands in for: it leaves with the tab bar before the
        // circles slide in, and comes back with it after they slide out.
        .animation(DSMotion.selectModeStep, value: directoryPath == nil)
    }

    @ViewBuilder
    private func bar(for directoryPath: String) -> some View {
        if store.selectedTab == .favorites {
            // Anchored on the favorited folder (the first pushed screen) after a Favorites crumb:
            // browsing from a favorite stays inside that subtree.
            BrowseBreadcrumbBar(
                directoryPath: directoryPath,
                rootTitle: store.favorites.path.first?.title ?? "",
                rootPath: store.favorites.path.first?.directoryPath ?? "",
                rootIcon: IconKit.folderFill,
                containerCrumb: (L10n.Favorites.navigationTitle, "", IconKit.starFill)
            ) { path, title in
                store.send(.favorites(.navigateToDirectory(path: path, title: title)))
            }
        } else {
            BrowseBreadcrumbBar(directoryPath: directoryPath) { path, title in
                store.send(.browse(.navigateToDirectory(path: path, title: title)))
            }
        }
    }
}

private enum PreviewSample {
    static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")

    @MainActor
    static func store(tab: MainTabFeature.Tab, pushed: [(path: String, title: String)]) -> StoreOf<MainTabFeature> {
        var state = MainTabFeature.State(
            serverURL: serverURL,
            user: User.preview
        )
        state.selectedTab = tab
        for screen in pushed {
            let folder = BrowseFeature.State(serverURL: serverURL, directoryPath: screen.path, title: screen.title)
            if tab == .favorites {
                state.favorites.path.append(folder)
            } else {
                state.browse.path.append(folder)
            }
        }
        return Store(initialState: state) { MainTabFeature() }
    }
}

#Preview("Browse, nested folder") {
    SplitDetailBreadcrumb(store: PreviewSample.store(
        tab: .browse,
        pushed: [("Photos", "Photos"), ("Photos/Vacation", "Vacation")]
    ))
    .frame(maxHeight: .infinity, alignment: .bottom)
}

#Preview("Browse, long path scrolls") {
    SplitDetailBreadcrumb(store: PreviewSample.store(
        tab: .browse,
        pushed: [("Photos/Vacation/2024/Summer/Beach/Day one/Morning", "Morning")]
    ))
    .frame(maxHeight: .infinity, alignment: .bottom)
}

#Preview("Inside a favorite") {
    SplitDetailBreadcrumb(store: PreviewSample.store(
        tab: .favorites,
        pushed: [("Media/Photos", "Photos"), ("Media/Photos/2024", "2024")]
    ))
    .frame(maxHeight: .infinity, alignment: .bottom)
}

#Preview("Root: hidden") {
    SplitDetailBreadcrumb(store: PreviewSample.store(tab: .browse, pushed: []))
        .frame(maxHeight: .infinity, alignment: .bottom)
}
