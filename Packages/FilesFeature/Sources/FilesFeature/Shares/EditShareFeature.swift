import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

/// Drives editing an existing share (the pushed `EditSharePage` on iOS, `MacEditShareSheet` on the
/// Mac), saving via `PUT /api/shares/:id`. The shared path can't change; the password's current
/// value is never shown (only a hash exists server side), so the field is keep / change / remove.
@Reducer
public struct EditShareFeature {
    /// The expiry choices above the calendar. `never` turns expiry off; `custom` is any date the
    /// presets don't produce.
    public enum ExpiryPreset: CaseIterable, Equatable, Sendable {
        case never
        case day
        case month
        case custom
    }

    /// A form problem shown beside the field it belongs to.
    public enum FieldError: Equatable, Sendable {
        case pastExpiration
        case passwordRequired
    }

    @ObservableState
    public struct State: Equatable, Identifiable {
        public let serverURL: URL
        public let share: Share
        /// When the page opened: the reference for the days left line and for an expired share.
        public let openedAt: Date
        /// The expiry the page opened on, which differs from the saved one for an expired share.
        let openedExpiryPreset: ExpiryPreset
        let openedExpiresAt: Date

        public var label: String
        public var accessChoice: ShareAccessChoice
        public var permissions: SharePermissions
        public var target: ShareTarget
        public var expiryPreset: ExpiryPreset
        public var expiresAt: Date
        public var isPasswordEnabled: Bool
        public var newPassword = ""

        public var shareableUsers: IdentifiedArrayOf<User> = []
        public var selectedUserIDs: Set<User.ID> = []
        public var usersPhase: DataPhase = .idle

        public var isSaving = false
        public var isConfirmingDiscard = false
        public var fieldError: FieldError?
        public var errorMessage: String?
        @Shared(.inMemory(SharedFeature.revisionKey)) var shareLinksRevision = 0

        public var id: Share.ID {
            share.id
        }

        public var accessMode: ShareAccessMode {
            accessChoice.accessMode
        }

        /// The label opens filled with the share's name. An expired share opens on Custom with a
        /// fresh date a week out, so bringing it back is one tap on Save.
        public init(serverURL: URL, share: Share, now: Date) {
            self.serverURL = serverURL
            self.share = share
            openedAt = now
            label = share.displayName
            accessChoice = ShareAccessChoice(accessMode: share.accessMode, permissions: share.permissions)
            permissions = share.permissions
            target = share.sharingType
            isPasswordEnabled = share.hasPassword
            selectedUserIDs = Set(share.permittedUserIds ?? [])
            let defaultExpiry = now.addingTimeInterval(CreateShareLinkFeature.defaultExpiryDays * Self.secondsPerDay)
            let opened: (preset: ExpiryPreset, date: Date) = switch share.expiresAt {
            case nil: (.never, defaultExpiry)
            case let date? where date <= now: (.custom, defaultExpiry)
            case let date?: (.custom, date)
            }
            expiryPreset = opened.preset
            expiresAt = opened.date
            openedExpiryPreset = opened.preset
            openedExpiresAt = opened.date
        }

        static let secondsPerDay: TimeInterval = 24 * 60 * 60

        public var isExpiryEnabled: Bool {
            expiryPreset != .never
        }

        /// The share had already stopped working when the page opened.
        public var isExpired: Bool {
            share.expiresAt.map { $0 <= openedAt } ?? false
        }

        /// Whole days from opening the page to the chosen expiry, rounded up.
        public var daysLeft: Int {
            max(0, Int((expiresAt.timeIntervalSince(openedAt) / Self.secondsPerDay).rounded(.up)))
        }

        var trimmedLabel: String {
            label.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The label to send: none while an unlabeled share still shows its prefilled name, so the
        /// link keeps following the item's own name.
        var savedLabel: String? {
            share.trimmedLabel == nil && trimmedLabel == share.displayName ? nil : trimmedLabel
        }

        /// Whether the draft differs from the share as saved, which is what Save sends.
        public var hasChanges: Bool {
            let isExpiryChanged = isExpiryEnabled
                ? share.expiresAt != expiresAt
                : share.expiresAt != nil
            return isChangedApartFromExpiry || isExpiryChanged
        }

        /// Whether the person changed anything since the page opened. An expired share opens
        /// already renewed, which Save would send, but leaving it untouched loses nothing.
        public var hasEdits: Bool {
            let isExpiryEdited = expiryPreset != openedExpiryPreset
                || (isExpiryEnabled && expiresAt != openedExpiresAt)
            return isChangedApartFromExpiry || isExpiryEdited
        }

        private var isChangedApartFromExpiry: Bool {
            let isPeopleChanged = target == .users && selectedUserIDs != Set(share.permittedUserIds ?? [])
            return savedLabel != share.trimmedLabel
                || accessMode != share.accessMode
                || permissions != share.permissions
                || target != share.sharingType
                || isPeopleChanged
                || isPasswordEnabled != share.hasPassword
                || !newPassword.isEmpty
        }

        /// Back and the sheet's swipe down ask first while there is something to lose.
        public var isLeavingGuarded: Bool {
            hasEdits || isSaving
        }

        var isPasswordMissing: Bool {
            isPasswordEnabled && !share.hasPassword && newPassword.isEmpty
        }

        var isSaveEnabled: Bool {
            guard !isSaving, hasChanges, !trimmedLabel.isEmpty else { return false }
            if target == .users {
                return !selectedUserIDs.isEmpty
            }
            return true
        }

        var selectedUsers: [User] {
            shareableUsers.filter { selectedUserIDs.contains($0.id) }
        }

        /// What to do with the password on save. A field left blank with the toggle still on keeps
        /// the current password; turning the toggle off on a protected share removes it.
        var passwordChange: UpdateShareRequest.PasswordChange {
            if target == .users {
                return share.hasPassword ? .remove : .keep
            }
            if isPasswordEnabled, !newPassword.isEmpty {
                return .set(newPassword)
            }
            if !isPasswordEnabled, share.hasPassword {
                return .remove
            }
            return .keep
        }
    }

    public enum Action: Equatable, Sendable {
        case task
        case labelChanged(String)
        case accessModeChanged(ShareAccessMode)
        case accessChoiceChanged(ShareAccessChoice)
        case permissionsChanged(SharePermissions)
        case targetChanged(ShareTarget)
        case wantsPasswordChanged(Bool)
        case newPasswordChanged(String)
        case expiryPresetTapped(ExpiryPreset)
        case expiryDaysTapped(Int)
        case expiryEnabledChanged(Bool)
        case expiresAtChanged(Date)
        case userToggled(User.ID)
        case shareableUsersResponse(Result<[User], FilesClientError>)
        case cancelTapped
        case discardConfirmed
        case discardCancelled
        case saveTapped
        case saveResponse(Result<Share, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case updated(Share)
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.date) var date
    @Dependency(\.calendar) var calendar
    @Dependency(\.dismiss) var dismiss

    private enum CancelID { case save }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return loadUsersIfNeeded(&state)

            case let .labelChanged(label):
                state.label = label
                return .none

            case let .accessModeChanged(mode):
                state.accessChoice = ShareAccessChoice(accessMode: mode, permissions: state.permissions)
                state.errorMessage = nil
                return .none

            case let .accessChoiceChanged(choice):
                state.permissions = choice.applied(to: state.permissions, from: state.accessChoice)
                state.accessChoice = choice
                state.errorMessage = nil
                return .none

            case let .permissionsChanged(permissions):
                state.permissions = permissions
                return .none

            case let .targetChanged(target):
                state.target = target
                state.errorMessage = nil
                return loadUsersIfNeeded(&state)

            case let .shareableUsersResponse(.success(users)):
                state.usersPhase = .loaded
                state.shareableUsers = IdentifiedArray(users, id: \.id, uniquingIDsWith: { first, _ in first })
                return .none

            case let .shareableUsersResponse(.failure(error)):
                state.usersPhase = .failed(error.userMessage)
                return .none

            case let .userToggled(id):
                if state.selectedUserIDs.contains(id) {
                    state.selectedUserIDs.remove(id)
                } else {
                    state.selectedUserIDs.insert(id)
                }
                return .none

            case let .wantsPasswordChanged(isOn):
                state.isPasswordEnabled = isOn
                if !isOn {
                    state.newPassword = ""
                    clear(.passwordRequired, in: &state)
                }
                return .none

            case let .newPasswordChanged(password):
                state.newPassword = password
                clear(.passwordRequired, in: &state)
                return .none

            case let .expiryPresetTapped(preset):
                state.expiryPreset = preset
                clear(.pastExpiration, in: &state)
                if let component = preset.component,
                   let presetDate = calendar.date(byAdding: component, value: 1, to: state.openedAt)
                {
                    state.expiresAt = presetDate
                }
                return .none

            case let .expiryDaysTapped(days):
                state.expiryPreset = .custom
                clear(.pastExpiration, in: &state)
                if let presetDate = calendar.date(byAdding: .day, value: days, to: state.openedAt) {
                    state.expiresAt = presetDate
                }
                return .none

            case let .expiryEnabledChanged(isEnabled):
                state.expiryPreset = isEnabled ? .custom : .never
                clear(.pastExpiration, in: &state)
                return .none

            case let .expiresAtChanged(newDate):
                state.expiresAt = newDate
                state.expiryPreset = .custom
                clear(.pastExpiration, in: &state)
                return .none

            case .cancelTapped:
                guard !state.isSaving else { return .none }
                guard state.hasEdits else { return leave() }
                state.isConfirmingDiscard = true
                return .none

            case .discardCancelled:
                state.isConfirmingDiscard = false
                return .none

            case .discardConfirmed:
                state.isConfirmingDiscard = false
                return leave()

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                if state.isPasswordMissing {
                    state.fieldError = .passwordRequired
                    return .none
                }
                if state.isExpiryEnabled, state.expiresAt <= date.now {
                    state.fieldError = .pastExpiration
                    return .none
                }
                state.isSaving = true
                state.fieldError = nil
                state.errorMessage = nil
                let request = UpdateShareRequest(
                    label: state.savedLabel,
                    accessMode: state.accessMode,
                    target: state.target,
                    expiresAt: state.isExpiryEnabled ? state.expiresAt : nil,
                    userIds: state.target == .users ? state.selectedUserIDs.sorted() : [],
                    password: state.passwordChange,
                    permissions: state.permissions
                )
                let serverURL = state.serverURL
                let shareID = state.share.id
                let filesClient = filesClient
                return .run { send in
                    try await send(.saveResponse(apiResult {
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

    /// Specific users needs the list of people to pick from; it loads once per page.
    private func loadUsersIfNeeded(_ state: inout State) -> Effect<Action> {
        guard state.target == .users, state.usersPhase.shouldLoadOnAppear else { return .none }
        state.usersPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.shareableUsersResponse(apiResult {
                try await filesClient.shareableUsers(serverURL)
            }))
        }
    }

    private func leave() -> Effect<Action> {
        let dismiss = dismiss
        return .run { _ in await dismiss() }
    }

    private func clear(_ error: FieldError, in state: inout State) {
        if state.fieldError == error {
            state.fieldError = nil
        }
    }
}

extension EditShareFeature.ExpiryPreset {
    /// How far a preset reaches from now; nil for the two that set no date of their own.
    var component: Calendar.Component? {
        switch self {
        case .day: .day
        case .month: .month
        case .never, .custom: nil
        }
    }
}
