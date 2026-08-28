import ComposableArchitecture
import Foundation
import Localization

/// The sheet shown after files are picked, before they're queued: the file list, the
/// destination folder (tap to push the folder picker), the total size, and the Upload button.
/// It never uploads — confirming hands `(files, destination)` up to `BrowseFeature`.
@Reducer
public struct UploadReviewFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var files: IdentifiedArrayOf<PickedFile>
        /// `""` means no folder chosen yet (the pick started at the root) — Upload stays
        /// disabled until the user picks one.
        public var destination: String
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init(serverURL: URL, files: [PickedFile], startingDestination: String) {
            self.serverURL = serverURL
            self.files = IdentifiedArray(uniqueElements: files)
            self.destination = startingDestination
        }

        public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
        public var canUpload: Bool { !files.isEmpty && !destination.isEmpty }
        public var hasDestination: Bool { !destination.isEmpty }
    }

    public enum Action: Equatable, Sendable {
        case pathTapped
        case folderPicker(PresentationAction<DestinationPickerFeature.Action>)
        case removeFileTapped(id: PickedFile.ID)
        case uploadTapped
        case cancelTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case confirmed(files: [PickedFile], destination: String)
            case cancelled
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pathTapped:
                state.folderPicker = DestinationPickerFeature.State(
                    serverURL: state.serverURL, uploadStartingAt: state.destination
                )
                return .none

            case let .folderPicker(.presented(.delegate(.confirmed(destination)))):
                state.destination = destination
                state.folderPicker = nil
                return .none

            case .folderPicker(.presented(.delegate(.cancelled))):
                state.folderPicker = nil
                return .none

            case .folderPicker:
                return .none

            case let .removeFileTapped(id):
                state.files.remove(id: id)
                return state.files.isEmpty ? .send(.delegate(.cancelled)) : .none

            case .uploadTapped:
                guard state.canUpload else { return .none }
                return .send(.delegate(.confirmed(files: Array(state.files), destination: state.destination)))

            case .cancelTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$folderPicker, action: \.folderPicker) {
            DestinationPickerFeature()
        }
    }
}
