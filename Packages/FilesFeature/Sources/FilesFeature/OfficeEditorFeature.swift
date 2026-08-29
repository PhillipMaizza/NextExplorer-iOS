import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Drives the full-screen office editor (`OfficeEditorView`). Fetches a launch payload from
/// `POST /api/{onlyoffice,collabora}/config` and hands it to a web view. The document server
/// (ONLYOFFICE) or WOPI host (Collabora) does the actual file fetch and save server side, so
/// there is nothing to persist here — on close the browse list just refetches.
@Reducer
public struct OfficeEditorFeature {
    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        public let serverURL: URL
        public let item: FileItem
        public let editor: OfficeEditor
        public let mode: OfficeEditorMode
        public var phase: Phase = .loading

        public var id: FileItem.ID { item.id }

        public init(serverURL: URL, item: FileItem, editor: OfficeEditor, mode: OfficeEditorMode) {
            self.serverURL = serverURL
            self.item = item
            self.editor = editor
            self.mode = mode
        }

        public enum Phase: Equatable, Sendable {
            case loading
            case onlyOffice(documentServerURL: URL, configJSON: Data)
            case collabora(url: URL)
            case failed(String)
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case configResponse(Result<State.Phase, FilesClientError>)
        case retryTapped
        case doneTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// `didEdit` is true when the session was writable, so the parent knows to refetch.
            case closed(didEdit: Bool)
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .retryTapped:
                state.phase = .loading
                let serverURL = state.serverURL
                let path = state.item.id
                let mode = state.mode
                let editor = state.editor
                let filesClient = self.filesClient
                return .run { send in
                    await send(.configResponse(await apiResult {
                        switch editor {
                        case .onlyOffice:
                            let launch = try await filesClient.fetchOnlyOfficeConfig(serverURL, path, mode)
                            return .onlyOffice(
                                documentServerURL: launch.documentServerURL,
                                configJSON: launch.configJSON
                            )
                        case .collabora:
                            let launch = try await filesClient.fetchCollaboraConfig(serverURL, path, mode)
                            return .collabora(url: launch.url)
                        }
                    }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .configResponse(.success(phase)):
                state.phase = phase
                return .none

            case let .configResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none

            case .doneTapped:
                return .send(.delegate(.closed(didEdit: state.mode == .edit)))

            case .delegate:
                return .none
            }
        }
    }
}
