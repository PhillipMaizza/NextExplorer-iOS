import CoreModels
import FilesClient
import Foundation

/// What an admin settings page needs from one load: the admin only settings, plus the server's
/// feature flags (the chunk size ceiling, and which switches an environment variable has locked).
/// The flags are optional because a failure to read them must not hide the settings themselves.
public struct ServerSettingsSnapshot: Equatable, Sendable {
    public var settings: SystemSettings
    public var features: ServerFeatures?

    public init(settings: SystemSettings, features: ServerFeatures? = nil) {
        self.settings = settings
        self.features = features
    }

    /// Reads the settings, then the feature flags, which are allowed to fail.
    static func load(_ filesClient: FilesClient, serverURL: URL) async throws -> ServerSettingsSnapshot {
        let settings = try await filesClient.fetchSystemSettings(serverURL)
        let features: ServerFeatures?
        do {
            features = try await filesClient.serverFeatures(serverURL)
        } catch {
            // A cancelled read is not a failed one, so it must not look like missing flags.
            if Task.isCancelled {
                throw CancellationError()
            }
            features = nil
        }
        return ServerSettingsSnapshot(settings: settings, features: features)
    }
}
