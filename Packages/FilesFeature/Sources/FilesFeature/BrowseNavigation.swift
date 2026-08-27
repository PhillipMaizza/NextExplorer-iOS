import ComposableArchitecture
import CoreModels
import Foundation

/// Shared helpers for the folder drill in navigation stack that `BrowseTabFeature` and
/// `FavoritesFeature` both host (a flat `StackState<BrowseFeature.State>`, one entry per
/// pushed subfolder). Centralises how a pushed browse screen is built.
enum BrowseNavigation {
    /// A pushed screen for drilling into `item`.
    static func screen(for item: FileItem, serverURL: URL) -> BrowseFeature.State {
        BrowseFeature.State(serverURL: serverURL, directoryPath: item.id, title: item.name)
    }

    /// Reset the stack and jump straight to an arbitrary path (e.g. a deep search result).
    /// An empty path just clears back to the root.
    static func jump(
        to path: String,
        title: String,
        serverURL: URL,
        stack: inout StackState<BrowseFeature.State>
    ) {
        stack.removeAll()
        guard !path.isEmpty else { return }
        stack.append(BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: title))
    }
}
