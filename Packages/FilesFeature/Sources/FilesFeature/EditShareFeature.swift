import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// Drives the "Edit Share Link" sheet (`EditShareSheet`) — the counterpart of
/// `CreateShareLinkFeature` for an existing share, saving via `PUT /api/shares/:id`. The
/// shared path can't change; the password's current value is never shown (only a hash
/// exists server side), so the field is keep / change / remove.
@Reducer
public struct EditShareFeature {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public let serverURL: URL
        public let share: Share

        public var label: String
        public var accessMode: ShareAccessMode
        public var target: ShareTarget
        public var isExpiryEnabled: Bool
        public var expiresAt: Date
        public var wantsPassword: Bool
        public var newPassword = ""

        public var shareableUsers: IdentifiedArrayOf<User> = []
        public var selectedUserIDs: Set<User.ID> = []
        public var isLoadingUsers = false
        public var hasLoadedUsers = false

        public var isSaving = false
        public var errorMessage: String?
        @Shared(.inMemory(SharedFeature.revisionKey)) var shareLinksRevision = 0

        public var id: Share.ID { share.id }

        public init(serverURL: URL, share: Share, now: Date = Date()) {
            self.serverURL = serverURL
            self.share = share
            self.label = share.label ?? ""
            self.accessMode = share.accessMode
            self.target = share.sharingType
            self.isExpiryEnabled = share.expiresAt != nil
            self.expiresAt = share.expiresAt ?? now.addingTimeInterval(CreateShareLinkFeature.defaultExpiryDays * 24 * 60 * 60)
            self.wantsPassword = share.hasPassword
            self.selectedUserIDs = Set(share.permittedUserIds ?? [])
        }

        var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

        var isSaveEnabled: Bool {
            guard !isSaving else { return false }
            if target == .users { return !selectedUserIDs.isEmpty }
            return true
        }

        /// What to do with the password on save. A still-on field left blank keeps the
        /// current password; turning the toggle off on a protected share removes it.
        var passwordChange: UpdateShareRequest.PasswordChange {
            if wantsPassword && !newPassword.isEmpty { return .set(newPassword) }
            if !wantsPassword && share.hasPassword { return .remove }
            return .keep
        }
    }

    public enum Action: Equatable, Sendable {
        case labelChanged(String)
        case accessModeChanged(ShareAccessMode)
        case targetChanged(ShareTarget)
        case wantsPasswordChanged(Bool)
        case newPasswordChanged(String)
        case expiryEnabledChanged(Bool)
        case expiresAtChanged(Date)
        case userToggled(User.ID)
        case shareableUsersResponse(Result<[User], FilesClientError>)
        case saveTapped
        case saveResponse(Result<Share, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case updated(Share)
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.date) var date

    private enum CancelID { case save }

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
                guard target == .users, !state.hasLoadedUsers, !state.isLoadingUsers else { return .none }
                state.isLoadingUsers = true
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.shareableUsersResponse(await apiResult {
                        try await filesClient.shareableUsers(serverURL)
                    }))
                }

            case let .shareableUsersResponse(.success(users)):
                state.isLoadingUsers = false
                state.hasLoadedUsers = true
                state.shareableUsers = IdentifiedArray(uniqueElements: users)
                return .none

            case let .shareableUsersResponse(.failure(error)):
                state.isLoadingUsers = false
                state.errorMessage = error.userMessage
                return .none

            case let .userToggled(id):
                if state.selectedUserIDs.contains(id) {
                    state.selectedUserIDs.remove(id)
                } else {
                    state.selectedUserIDs.insert(id)
                }
                return .none

            case let .wantsPasswordChanged(isOn):
                state.wantsPassword = isOn
                if !isOn { state.newPassword = "" }
                return .none

            case let .newPasswordChanged(password):
                state.newPassword = password
                return .none

            case let .expiryEnabledChanged(isEnabled):
                state.isExpiryEnabled = isEnabled
                return .none

            case let .expiresAtChanged(newDate):
                state.expiresAt = newDate
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                if state.isExpiryEnabled, state.expiresAt <= date.now {
                    state.errorMessage = L10n.CreateShare.errorPastExpiration
                    return .none
                }
                state.isSaving = true
                state.errorMessage = nil
                let request = UpdateShareRequest(
                    label: state.trimmedLabel.isEmpty ? nil : state.trimmedLabel,
                    accessMode: state.accessMode,
                    target: state.target,
                    expiresAt: state.isExpiryEnabled ? state.expiresAt : nil,
                    userIds: state.target == .users ? Array(state.selectedUserIDs) : [],
                    password: state.passwordChange
                )
                let serverURL = state.serverURL
                let shareID = state.share.id
                let filesClient = self.filesClient
                return .run { send in
                    await send(.saveResponse(await apiResult {
                        try await filesClient.updateShareLink(serverURL, shareID, request)
                    }))
                }
                .cancellable(id: CancelID.save, cancelInFlight: true)

            case let .saveResponse(.success(updated)):
                state.isSaving = false
                state.$shareLinksRevision.withLock { $0 += 1 }
                return .send(.delegate(.updated(updated)))

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
