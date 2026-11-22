import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// The optional programs the server found (`GET /api/capabilities`, admin only), read only.
/// Mirrors the About page of the web client.
@Reducer
public struct ServerToolsFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var tools: [ServerCapability] = []
        public var phase: DataPhase = .idle

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadResponse(Result<[ServerCapability], FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase.shouldLoadOnAppear else { return .none }
                state.phase = .loading
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.loadResponse(apiResult { try await filesClient.fetchCapabilities(serverURL) }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loadResponse(.success(tools)):
                state.tools = tools.sorted {
                    ($0.status, $0.name.lowercased()) < ($1.status, $1.name.lowercased())
                }
                state.phase = .loaded
                return .none

            case let .loadResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none
            }
        }
    }
}
