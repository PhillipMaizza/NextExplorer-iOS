#if os(macOS)
    import ComposableArchitecture
    import Foundation
    import Localization

    enum FolderContentsChange: Equatable, Sendable {
        case folders([String])
        case everything
    }

    extension BrowseFeature {
        static func folderContentsChange(after action: Action, directoryPath: String) -> FolderContentsChange? {
            switch action {
            case .renameResponse(.success), .newFolderResponse(.success), .newFileResponse(.success),
                 .deleteResponse(.success),
                 .bulkDeleteResponse(.success), .extractResponse(.success), .compressResponse(.success),
                 .textSaveResponse(_, .success):
                .folders([directoryPath])
            case .transferResponse(.success), .undoResponse(.success), .redoResponse(.success):
                .everything
            default:
                nil
            }
        }
    }

    extension BrowseTabFeature {
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
        static func macSavedMessage(count: Int, lastSavedURL: URL) -> String {
            let folderName = lastSavedURL.deletingLastPathComponent().lastPathComponent
            return count == 1
                ? L10n.Browse.downloadSavedTo(folderName)
                : L10n.Browse.downloadSavedAllTo(count, folderName)
        }

        static func syncSections(after action: Action, in state: State) -> Effect<Action> {
            if case let .browse(browseAction) = action,
               let change = BrowseTabFeature.folderContentsChange(after: browseAction, in: state.browse)
            {
                return FavoritesFeature.refresh(for: change).map(Action.favorites)
            }
            if case let .favorites(favoritesAction) = action,
               let change = FavoritesFeature.folderContentsChange(after: favoritesAction, in: state.favorites)
            {
                return BrowseTabFeature.refresh(for: change).map(Action.browse)
            }
            return .none
        }
    }

    extension FavoritesFeature {
        static func folderContentsChange(after action: Action, in state: State) -> FolderContentsChange? {
            guard case let .path(.element(id, screenAction)) = action,
                  let screen = state.path[id: id] else { return nil }
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
