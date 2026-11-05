#if os(macOS)
    import ComposableArchitecture
    import Foundation
    import Localization

    /// Which folder listings a finished change made stale, so every other Mac window showing
    /// them reloads: a rename, delete or upload in one window shows up in the rest.
    public enum FolderContentsChange: Equatable, Sendable {
        case folders([String])
        /// A move, copy or undo can reach folders beyond the one on screen.
        case everything
    }

    /// The latest change, broadcast from the main store to the extra Browse windows. `origin`
    /// is the window that made it (`nil` for the main window), which already shows it.
    public struct FolderWindowSync: Equatable, Sendable {
        public var revision = 0
        public var change = FolderContentsChange.folders([])
        public var origin: UUID?

        mutating func broadcast(_ change: FolderContentsChange, from origin: UUID?) {
            revision += 1
            self.change = change
            self.origin = origin
        }
    }

    extension BrowseFeature {
        /// The folders `action` changed on the server, once it has finished; `nil` when it
        /// changed nothing. A failure leaves the listings as they were.
        static func folderContentsChange(after action: Action, directoryPath: String) -> FolderContentsChange? {
            switch action {
            case .renameResponse(.success), .newFolderResponse(.success), .deleteResponse(.success),
                 .bulkDeleteResponse(.success), .extractZipResponse(.success), .compressResponse(.success),
                 .textSaveResponse(.success):
                .folders([directoryPath])
            case .transferResponse(.success), .undoResponse(.success):
                .everything
            default:
                nil
            }
        }
    }

    extension BrowseTabFeature {
        /// The change a screen in this stack just finished, if any.
        static func folderContentsChange(after action: Action, in state: State) -> FolderContentsChange? {
            switch action {
            case let .root(screenAction):
                BrowseFeature.folderContentsChange(after: screenAction, directoryPath: state.root.directoryPath)
            case let .path(.element(id, screenAction)):
                state.path[id: id].flatMap {
                    BrowseFeature.folderContentsChange(after: screenAction, directoryPath: $0.directoryPath)
                }
            default:
                nil
            }
        }

        /// Reloads whatever this stack shows of a change made elsewhere.
        static func refresh(for change: FolderContentsChange) -> Effect<Action> {
            switch change {
            case let .folders(paths):
                .merge(paths.map { .send(.refreshDirectory(path: $0)) })
            case .everything:
                .send(.syncPathStack)
            }
        }
    }

    extension MainTabFeature {
        /// "Saved to Desktop" or "Saved 3 items to Desktop": the folder the last save went into.
        static func macSavedMessage(count: Int, lastSavedURL: URL) -> String {
            let folderName = lastSavedURL.deletingLastPathComponent().lastPathComponent
            return count == 1
                ? L10n.Browse.downloadSavedTo(folderName)
                : L10n.Browse.downloadSavedAllTo(count, folderName)
        }

        /// A change finished in this window: broadcast it to the extra Browse windows, and
        /// reload the other section here when it shows the same folder (Browse and a pushed
        /// Favorites folder can both be open on it).
        static func syncFolderWindows(_ state: inout State, after action: Action) -> Effect<Action> {
            if case let .uploads(.delegate(.queueFinished(summary))) = action, !summary.changedPaths.isEmpty {
                state.folderWindowSync.broadcast(.folders(summary.changedPaths.sorted()), from: nil)
                return .none
            }
            if case let .browse(browseAction) = action,
               let change = BrowseTabFeature.folderContentsChange(after: browseAction, in: state.browse)
            {
                state.folderWindowSync.broadcast(change, from: nil)
                return FavoritesFeature.refresh(for: change).map(Action.favorites)
            }
            if case let .favorites(favoritesAction) = action,
               let change = FavoritesFeature.folderContentsChange(after: favoritesAction, in: state.favorites)
            {
                state.folderWindowSync.broadcast(change, from: nil)
                return BrowseTabFeature.refresh(for: change).map(Action.browse)
            }
            return .none
        }
    }

    extension FavoritesFeature {
        /// The change a pushed screen in Favorites just finished, if any.
        static func folderContentsChange(after action: Action, in state: State) -> FolderContentsChange? {
            guard case let .path(.element(id, screenAction)) = action, let screen = state.path[id: id] else { return nil }
            return BrowseFeature.folderContentsChange(after: screenAction, directoryPath: screen.directoryPath)
        }

        static func refresh(for change: FolderContentsChange) -> Effect<Action> {
            switch change {
            case let .folders(paths):
                .merge(paths.map { .send(.refreshDirectory(path: $0)) })
            case .everything:
                .send(.syncPathStack)
            }
        }
    }
#endif
