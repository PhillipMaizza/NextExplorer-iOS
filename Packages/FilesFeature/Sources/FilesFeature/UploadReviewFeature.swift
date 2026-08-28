import ComposableArchitecture
import Foundation
import Localization

/// The sheet shown after files are picked, before they're queued: the file list, the
/// destination folder (tap to push the folder picker), the total size, and the Upload button.
/// It never uploads — confirming hands `(files, destination)` up to `BrowseFeature`.
///
/// The sheet is presented *immediately* on pick and fills in as files are materialized
/// (copied out of the picker, photos read into memory) — heavy items would otherwise stall it
/// behind the copy.
@Reducer
public struct UploadReviewFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var files: IdentifiedArrayOf<PickedFile>
        /// Files still being copied out of the picker. `files` grows as each lands.
        public var preparingCount: Int
        /// `""` means no folder chosen yet (the pick started at the root) — Upload stays
        /// disabled until the user picks one.
        public var destination: String
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init(serverURL: URL, files: [PickedFile] = [], startingDestination: String, preparingCount: Int = 0) {
            self.serverURL = serverURL
            self.files = IdentifiedArray(uniqueElements: files)
            self.destination = startingDestination
            self.preparingCount = preparingCount
        }

        public var isPreparing: Bool { preparingCount > 0 }
        /// Total files the sheet is about, including ones still being prepared.
        public var totalCount: Int { files.count + preparingCount }
        public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
        public var canUpload: Bool { !isPreparing && !files.isEmpty && !destination.isEmpty }
        public var hasDestination: Bool { !destination.isEmpty }
    }

    public enum Action: Equatable, Sendable {
        case filePrepared(PickedFile)
        case preparationFinished
        /// "Add more files" from inside the sheet — a fresh pick of `count` items is now being
        /// materialized on top of what's already staged.
        case addMoreRequested(count: Int)
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
            case let .filePrepared(file):
                state.files.append(file)
                state.preparingCount = max(0, state.preparingCount - 1)
                return .none

            case .preparationFinished:
                state.preparingCount = 0
                return state.files.isEmpty ? .send(.delegate(.cancelled)) : .none

            case let .addMoreRequested(count):
                state.preparingCount += max(0, count)
                return .none

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
                return state.files.isEmpty && !state.isPreparing ? .send(.delegate(.cancelled)) : .none

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
