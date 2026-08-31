import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// An admin editing the server's path-scoped access rules via `PATCH /api/settings`. Mirrors
/// the web client's `SettingsAccessControl.vue`. The rule array is replaced wholesale on
/// save; the server normalises paths and drops empty ones, then echoes the result.
@Reducer
public struct AccessRulesFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        /// Last known from the server; the baseline `isDirty` compares against. `nil` until
        /// the first load succeeds.
        public var loaded: [AccessRule]?
        public var drafts: IdentifiedArrayOf<AccessRule> = []
        public var phase: DataPhase = .idle
        public var isSaving = false
        /// Save failures only; a load failure lives in `phase`.
        public var errorMessage: String?
        public var isUnavailable = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var isDirty: Bool {
            guard let loaded else { return false }
            return Array(drafts) != loaded
        }

        var isSaveEnabled: Bool { isDirty && !isSaving }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case settingsResponse(Result<SystemSettings, FilesClientError>)
        case addRuleTapped
        case removeRule(id: AccessRule.ID)
        case pathChanged(id: AccessRule.ID, String)
        case recursiveToggled(id: AccessRule.ID, Bool)
        case permissionChanged(id: AccessRule.ID, AccessRule.Permission)
        case saveTapped
        case saveResponse(Result<[AccessRule], FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case saved
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.uuid) var uuid

    private enum CancelID { case load, save }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.phase = .loading
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.settingsResponse(try await apiResult {
                        try await filesClient.fetchSystemSettings(serverURL)
                    }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .settingsResponse(.success(settings)):
                state.phase = .loaded
                // `access.rules` is admin only; an empty array from a non-admin is
                // indistinguishable from an admin with no rules, so treat a response that
                // also lacks `thumbnails` as "not an admin".
                if settings.thumbnails == nil && settings.accessRules.isEmpty {
                    state.isUnavailable = true
                    return .none
                }
                if !state.isDirty {
                    state.loaded = settings.accessRules
                    state.drafts = IdentifiedArray(uniqueElements: settings.accessRules)
                } else {
                    state.loaded = settings.accessRules
                }
                return .none

            case let .settingsResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none

            case .addRuleTapped:
                state.drafts.append(AccessRule(
                    id: uuid().uuidString,
                    path: "",
                    isRecursive: true,
                    permission: .readOnly
                ))
                state.errorMessage = nil
                return .none

            case let .removeRule(id):
                state.drafts.remove(id: id)
                state.errorMessage = nil
                return .none

            case let .pathChanged(id, value):
                state.drafts[id: id]?.path = value
                state.errorMessage = nil
                return .none

            case let .recursiveToggled(id, value):
                state.drafts[id: id]?.isRecursive = value
                return .none

            case let .permissionChanged(id, permission):
                state.drafts[id: id]?.permission = permission
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let rules = state.drafts
                    .map { rule -> AccessRule in
                        var trimmed = rule
                        trimmed.path = rule.path.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed
                    }
                    .filter { !$0.path.isEmpty }
                let filesClient = self.filesClient
                return .run { send in
                    await send(.saveResponse(try await apiResult {
                        try await filesClient.updateAccessRules(serverURL, rules)
                    }))
                }
                .cancellable(id: CancelID.save, cancelInFlight: true)

            case let .saveResponse(.success(rules)):
                state.isSaving = false
                state.loaded = rules
                state.drafts = IdentifiedArray(uniqueElements: rules)
                return .send(.delegate(.saved))

            case let .saveResponse(.failure(error)):
                state.isSaving = false
                state.errorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
