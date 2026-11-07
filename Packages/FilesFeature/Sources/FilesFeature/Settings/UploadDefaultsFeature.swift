import ComposableArchitecture
import CoreModels
import FolderPickerFeature
import Foundation
import ShareUploads

/// Settings for files shared to NextExplorer from other apps (the Share Extension and "Open in
/// NextExplorer"), per account: the folder they start in, and whether to upload there without
/// asking. Stored in the App Group, where the extension reads it.
@Reducer
public struct UploadDefaultsFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        /// `SessionCredentials.accountID` of the signed in account.
        public var accountID: String
        public var defaults = UploadDefaults()
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init(serverURL: URL, accountID: String) {
            self.serverURL = serverURL
            self.accountID = accountID
        }

        public var hasFolder: Bool {
            !(defaults.folderPath ?? "").isEmpty
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case chooseFolderTapped
        case askEachTimeTapped
        case uploadsWithoutAskingChanged(Bool)
        case folderPicker(PresentationAction<DestinationPickerFeature.Action>)
    }

    @Dependency(\.uploadDefaults) var uploadDefaults

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.defaults = uploadDefaults.load(state.accountID)
                return .none

            case .chooseFolderTapped:
                state.folderPicker = DestinationPickerFeature.State(
                    serverURL: state.serverURL,
                    uploadStartingAt: state.defaults.folderPath ?? ""
                )
                return .none

            case let .folderPicker(.presented(.delegate(.confirmed(destination)))):
                state.folderPicker = nil
                state.defaults.folderPath = destination
                return save(state)

            case .folderPicker(.presented(.delegate(.cancelled))):
                state.folderPicker = nil
                return .none

            case .folderPicker:
                return .none

            case .askEachTimeTapped:
                state.defaults = UploadDefaults()
                return save(state)

            case let .uploadsWithoutAskingChanged(isOn):
                guard state.hasFolder || !isOn else { return .none }
                state.defaults.uploadsWithoutAsking = isOn
                return save(state)
            }
        }
        .ifLet(\.$folderPicker, action: \.folderPicker) {
            DestinationPickerFeature()
        }
    }

    private func save(_ state: State) -> Effect<Action> {
        let uploadDefaults = uploadDefaults
        let accountID = state.accountID
        let defaults = state.defaults
        return .run { _ in uploadDefaults.save(accountID, defaults) }
    }
}
