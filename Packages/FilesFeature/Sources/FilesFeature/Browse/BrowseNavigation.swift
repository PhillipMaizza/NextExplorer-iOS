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

/// A folder stack with Finder style history: Back, Forward and Enclosing Folder. `BrowseTabFeature`
/// and `FavoritesFeature` both host one.
protocol BrowseHistoryState {
    var path: StackState<BrowseFeature.State> { get set }
    /// Folders left by going back, nearest last, so Forward (⌘]) can reopen them.
    var forwardStack: [BrowseFeature.State] { get set }
}

extension BrowseHistoryState {
    /// Back (⌘[): the visible folder leaves the stack, and Forward can reopen it.
    mutating func goBack() {
        guard let id = path.ids.last else { return }
        if let screen = path[id: id] {
            forwardStack.append(screen)
        }
        path.pop(from: id)
    }

    /// Forward (⌘]): reopens the folder last left by going back.
    mutating func goForward() {
        guard let screen = forwardStack.popLast() else { return }
        path.append(screen)
    }

    /// Leaving with the toolbar's Back pops everything from `id` up; those levels can come back
    /// with Forward, the nearest first.
    mutating func recordPop(from id: StackElementID) {
        guard let start = path.ids.firstIndex(of: id) else { return }
        forwardStack.append(contentsOf: path.ids[start...].compactMap { path[id: $0] }.reversed())
    }

    /// Enclosing Folder (⌘↑): the folder that holds the visible one. Usually that is the screen
    /// under it, which makes this Back; after a jump straight to a deep folder (Go to Folder, a
    /// search result) the parent is opened in place instead. `isFirstScreenTop` says the bottom
    /// screen has no parent of its own here, as a favorite's folder in Favorites.
    mutating func goToEnclosingFolder(serverURL: URL, isFirstScreenTop: Bool = false) {
        guard let top = path.last else { return }
        let parent = (top.directoryPath as NSString).deletingLastPathComponent
        let below = path.count > 1 ? path[id: path.ids[path.ids.count - 2]] : nil
        if below?.directoryPath == parent || (path.count == 1 && (parent.isEmpty || isFirstScreenTop)) {
            goBack()
            return
        }
        forwardStack = []
        if parent.isEmpty {
            path.removeAll()
            return
        }
        path.removeLast()
        path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: parent, title: (parent as NSString).lastPathComponent))
    }
}

extension BrowseTabFeature.State: BrowseHistoryState {}
extension FavoritesFeature.State: BrowseHistoryState {}
