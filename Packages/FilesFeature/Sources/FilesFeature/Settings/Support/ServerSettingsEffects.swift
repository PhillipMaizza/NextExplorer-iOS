import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

extension DataPhase {
    /// A page that already shows its form stays on it while it reads again, so a reload never
    /// brings the spinner or a failure card over what is being edited.
    mutating func beginReload() {
        if self != .loaded {
            self = .loading
        }
    }
}

extension Effect where Action: Sendable {
    /// One request that answers with an action carrying its result. A newer call under the same id
    /// replaces one still running. A cancelled call answers with nothing, since leaving the screen
    /// is not a failure.
    static func api<Value: Sendable>(
        cancelID: some Hashable & Sendable,
        operation: @escaping @Sendable () async throws -> Value,
        response: @escaping @Sendable (Result<Value, FilesClientError>) -> Action
    ) -> Effect<Action> {
        .run { send in
            try await send(response(apiResult(operation)))
        }
        .cancellable(id: cancelID, cancelInFlight: true)
    }

    /// Reads the settings with the server's feature flags, which may fail without failing the read.
    static func loadSnapshot(
        _ filesClient: FilesClient,
        serverURL: URL,
        cancelID: some Hashable & Sendable,
        response: @escaping @Sendable (Result<ServerSettingsSnapshot, FilesClientError>) -> Action
    ) -> Effect<Action> {
        .api(
            cancelID: cancelID,
            operation: { try await ServerSettingsSnapshot.load(filesClient, serverURL: serverURL) },
            response: response
        )
    }

    /// Reads the settings alone.
    static func loadSettings(
        _ filesClient: FilesClient,
        serverURL: URL,
        cancelID: some Hashable & Sendable,
        response: @escaping @Sendable (Result<SystemSettings, FilesClientError>) -> Action
    ) -> Effect<Action> {
        .api(
            cancelID: cancelID,
            operation: { try await filesClient.fetchSystemSettings(serverURL) },
            response: response
        )
    }

    /// Sends a patch and answers with the one section the server echoed back, and stops a read in
    /// flight so its older answer cannot land over what was just saved.
    static func saveSettings<Saved: Sendable>(
        _ filesClient: FilesClient,
        serverURL: URL,
        patch: SystemSettingsPatch,
        section: @escaping @Sendable (SystemSettings) -> Saved?,
        missingMessage: String,
        cancelLoad: some Hashable & Sendable,
        cancelID: some Hashable & Sendable,
        response: @escaping @Sendable (Result<Saved, FilesClientError>) -> Action
    ) -> Effect<Action> {
        .merge(
            .cancel(id: cancelLoad),
            .api(
                cancelID: cancelID,
                operation: {
                    let echoed = try await filesClient.updateSystemSettings(serverURL, patch)
                    guard let saved = section(echoed) else {
                        throw FilesClientError.decoding(missingMessage)
                    }
                    return saved
                },
                response: response
            )
        )
    }
}
