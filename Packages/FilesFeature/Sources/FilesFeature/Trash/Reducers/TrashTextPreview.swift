import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// A text file in the trash, read before deciding what to do with it. Read only: nothing can be
/// written into the trash. Files the editor would not open are not offered.
public enum TrashTextPreview {
    public enum State: Equatable, Sendable {
        case closed
        case loading(name: String)
        case loaded(TrashText)

        public var isPresented: Bool {
            self != .closed
        }

        /// The answer for the file still waiting; a late one after closing is dropped. Returns the
        /// failure to tell the user about, if any.
        mutating func receive(_ result: Result<TrashText, FilesClientError>) -> FilesClientError? {
            guard case .loading = self else { return nil }
            switch result {
            case let .success(text):
                self = .loaded(text)
                return nil
            case let .failure(error):
                self = .closed
                return error
            }
        }
    }

    /// Whether a file of this name opens here: the editor's text files only.
    static func canOpen(name: String) -> Bool {
        EditableTextFiles.isEditable(name: name)
    }

    /// Starts loading `path` inside `item` ("" for the item itself); callers check `canOpen` first.
    static func open(
        _ state: inout State,
        name: String,
        itemID: TrashItem.ID,
        path: String,
        serverURL: URL,
        filesClient: FilesClient
    ) -> Effect<Result<TrashText, FilesClientError>> {
        state = .loading(name: name)
        return .run { send in
            try await send(apiResult { try await filesClient.fetchTrashText(serverURL, itemID, path) })
        }
    }
}
