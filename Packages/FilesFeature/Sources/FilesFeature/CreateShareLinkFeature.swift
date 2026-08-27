import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Drives the "Create Share Link" sheet (`CreateShareLinkSheet`) — mirrors the web client's
/// `ShareDialog.vue`. Two phases in one state: the form, then the created-link confirmation
/// (`createdShare != nil`). Verified request/response shapes: [[share-link-api]].
@Reducer
public struct CreateShareLinkFeature {
    /// Days ahead the expiration date defaults to when the user first enables it.
    static let defaultExpiryDays: Double = 7

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var itemName: String
        public var itemPath: String
        public var isDirectory: Bool

        public var label: String
        public var accessMode: ShareAccessMode = .readonly
        public var target: ShareTarget = .anyone
        public var isPasswordEnabled = false
        public var password = ""
        public var isExpiryEnabled = false
        public var expiresAt: Date

        public var isCreating = false
        public var errorMessage: String?
        public var createdShare: CreatedShare?
        public var directLinkMode: DirectLinkMode = .auto

        public init(serverURL: URL, itemName: String, itemPath: String, isDirectory: Bool, now: Date = Date()) {
            self.serverURL = serverURL
            self.itemName = itemName
            self.itemPath = itemPath
            self.isDirectory = isDirectory
            self.label = itemName
            self.expiresAt = now.addingTimeInterval(defaultExpiryDays * 24 * 60 * 60)
        }

        /// Full logical path of the shared item — parent path plus name, matching the
        /// server's `sourcePath` expectation.
        public var sourcePath: String {
            itemPath.isEmpty ? itemName : "\(itemPath)/\(itemName)"
        }

        /// "Specific users" has no picker yet, so it can't be submitted.
        public var isTargetSupported: Bool {
            target == .anyone
        }

        public var isCreateEnabled: Bool {
            !isCreating && isTargetSupported
        }

        public var directLink: URL? {
            createdShare?.directLink(mode: directLinkMode)
        }
    }

    public enum Action: Equatable, Sendable {
        case labelChanged(String)
        case accessModeChanged(ShareAccessMode)
        case targetChanged(ShareTarget)
        case passwordEnabledChanged(Bool)
        case passwordChanged(String)
        case expiryEnabledChanged(Bool)
        case expiresAtChanged(Date)
        case directLinkModeChanged(DirectLinkMode)
        case createTapped
        case createResponse(Result<CreatedShare, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .labelChanged(label):
                state.label = label
                return .none

            case let .accessModeChanged(mode):
                state.accessMode = mode
                state.errorMessage = nil
                return .none

            case let .targetChanged(target):
                state.target = target
                state.errorMessage = nil
                return .none

            case let .passwordEnabledChanged(isEnabled):
                state.isPasswordEnabled = isEnabled
                return .none

            case let .passwordChanged(password):
                state.password = password
                return .none

            case let .expiryEnabledChanged(isEnabled):
                state.isExpiryEnabled = isEnabled
                return .none

            case let .expiresAtChanged(date):
                state.expiresAt = date
                return .none

            case let .directLinkModeChanged(mode):
                state.directLinkMode = mode
                return .none

            case .createTapped:
                guard state.isCreateEnabled else { return .none }
                if state.isExpiryEnabled, state.expiresAt <= date.now {
                    state.errorMessage = "Pick an expiration date in the future."
                    return .none
                }
                state.isCreating = true
                state.errorMessage = nil
                let request = CreateShareLinkRequest(
                    sourcePath: state.sourcePath,
                    label: state.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : state.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    accessMode: state.accessMode,
                    target: state.target,
                    password: state.isPasswordEnabled && !state.password.isEmpty ? state.password : nil,
                    userIds: [],
                    expiresAt: state.isExpiryEnabled ? state.expiresAt : nil
                )
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    do {
                        let created = try await filesClient.createShareLink(serverURL, request)
                        await send(.createResponse(.success(created)), animation: .default)
                    } catch {
                        await send(.createResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                    }
                }

            case let .createResponse(.success(created)):
                state.isCreating = false
                state.createdShare = created
                return .none

            case let .createResponse(.failure(error)):
                state.isCreating = false
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }
}
