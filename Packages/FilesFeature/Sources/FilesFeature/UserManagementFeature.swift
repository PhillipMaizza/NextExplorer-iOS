import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import Localization
import SwiftUI

/// Admin only user management, reachable from Settings for a signed in admin. Mirrors the web
/// client's `AdminUsers` / `UserList` / `UserDetail` screens: a list of every user, then a
/// detail screen with Profile, Security and (with the `USER_VOLUMES` feature) Volumes tabs.
///
/// Backed by the admin endpoints under `/api/users`, verified against
/// `backend/src/routes/users.js` and `backend/src/routes/userVolumes.js`. The server rejects
/// demoting an admin (a `PATCH` dropping `admin` always 400s), so this screen only grants.
@Reducer
public struct UserManagementFeature {
    private enum CancelID: Hashable {
        /// User list and feature flag load. A new load supersedes any in flight one.
        case load
        /// Per user volume loads, so switching users mid fetch can't land stale volumes.
        case volumes
        /// Profile save, grant admin and delete for the open detail user, cancelled with the detail.
        case userMutation
        /// Volume assign, update and remove for the open detail user, cancelled with the detail.
        case volumeMutation
        /// Create user sheet submission.
        case createUser
        /// Set password sheet submission.
        case setPassword
    }

    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case type
        case name
        case email

        var title: String {
            switch self {
            case .type: L10n.UserManagement.sortType
            case .name: L10n.UserManagement.sortName
            case .email: L10n.UserManagement.sortEmail
            }
        }

        var icon: Image {
            switch self {
            case .type: IconKit.shield
            case .name: IconKit.textformat
            case .email: IconKit.envelope
            }
        }
    }

    public enum DetailTab: String, Hashable, Sendable, CaseIterable {
        case profile
        case security
        case volumes

        var title: String {
            switch self {
            case .profile: L10n.UserManagement.tabProfile
            case .security: L10n.UserManagement.tabSecurity
            case .volumes: L10n.UserManagement.tabVolumes
            }
        }
    }

    /// Local state for the "Create User" sheet.
    public struct CreateUserState: Equatable, Sendable {
        public var email = ""
        public var username = ""
        public var password = ""
        public var isAdmin = false
        public var isSubmitting = false
        public var errorMessage: String?

        /// Inline field errors, shown only once the user has typed something. An empty field
        /// is "not yet filled in", not "wrong".
        var emailError: String? {
            email.trimmed.isEmpty || CredentialRules.isEmailShaped(email) ? nil : L10n.UserManagement.errorEmailInvalid
        }
        var passwordError: String? {
            password.isEmpty || CredentialRules.isPasswordLongEnough(password)
                ? nil
                : L10n.UserManagement.errorPasswordTooShort(CredentialRules.minimumPasswordLength)
        }
        var isSubmitEnabled: Bool {
            CredentialRules.isEmailShaped(email)
                && CredentialRules.isPasswordLongEnough(password)
                && !isSubmitting
        }
    }

    /// Local state for the set or reset password sheet.
    public struct PasswordSheetState: Equatable, Sendable {
        public var userID: String
        public var userLabel: String
        public var hasExistingPassword: Bool
        public var password = ""
        public var isSubmitting = false
        public var errorMessage: String?

        var passwordError: String? {
            password.isEmpty || CredentialRules.isPasswordLongEnough(password)
                ? nil
                : L10n.UserManagement.errorPasswordTooShort(CredentialRules.minimumPasswordLength)
        }
        var isSubmitEnabled: Bool { CredentialRules.isPasswordLongEnough(password) && !isSubmitting }
    }

    /// Local state for the Assign or Edit Volume sheet. `editingVolumeID == nil` means add.
    public struct VolumeSheetState: Equatable, Sendable {
        public var userID: String
        public var editingVolumeID: String?
        public var label = ""
        public var selectedPath = ""
        public var accessMode: ShareAccessMode = .readwrite
        public var isSubmitting = false
        public var errorMessage: String?

        var isEditing: Bool { editingVolumeID != nil }
        var isSubmitEnabled: Bool {
            !label.trimmed.isEmpty && !selectedPath.trimmed.isEmpty && !isSubmitting
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public let currentUserID: String

        public var users: IdentifiedArrayOf<User> = []
        public var isLoading = false
        public var errorMessage: String?
        public var searchQuery = ""
        public var sortOption: SortOption = .type
        public var sortDirection: BrowseFeature.SortDirection = .ascending
        public var isUserVolumesEnabled = false
        /// Whether `GET /api/features` has answered at least once. The flag load is best effort
        /// and shouldn't block the user list, so a failed one is retried once when a detail
        /// screen opens.
        public var hasLoadedFeatures = false

        public var detailUserID: User.ID?
        public var detailTab: DetailTab = .profile
        public var detailErrorMessage: String?

        // Profile form, seeded from the selected user each time detail opens.
        public var editDisplayName = ""
        public var editUsername = ""
        public var editEmail = ""
        public var isSavingProfile = false
        public var isUpdatingRoles = false

        // Volumes tab.
        public var volumes: IdentifiedArrayOf<UserVolume> = []
        public var isLoadingVolumes = false
        /// Whether the current detail user's volumes have been fetched. Stops a user with
        /// genuinely zero volumes from hitting the endpoint again on every tab switch.
        public var hasLoadedVolumesForDetail = false
        public var volumeToRemove: UserVolume?

        // Confirmations and sheets.
        public var userToDelete: User?
        public var createSheet: CreateUserState?
        public var passwordSheet: PasswordSheetState?
        public var volumeSheet: VolumeSheetState?

        /// Set by a successful mutation; the view turns it into a toast, then clears it.
        public var toast: String?

        public init(serverURL: URL, currentUserID: String) {
            self.serverURL = serverURL
            self.currentUserID = currentUserID
        }

        public var detailUser: User? {
            detailUserID.flatMap { users[id: $0] }
        }

        public var isViewingOwnAccount: Bool {
            detailUserID == currentUserID
        }

        /// Substring filter on display name, username and email, then sorted per the sort
        /// sheet. `.type` puts admins first, then by name; the direction flips the whole list.
        public var displayedUsers: [User] {
            let query = searchQuery.trimmed.lowercased()
            let base = query.isEmpty ? Array(users) : users.filter { user in
                let haystack = [user.displayName, user.username, user.email]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")
                return haystack.contains(query)
            }
            let sorted = base.sorted { lhs, rhs in
                switch sortOption {
                case .type where lhs.isAdmin != rhs.isAdmin:
                    return lhs.isAdmin && !rhs.isAdmin
                case .email:
                    let cmp = (lhs.email ?? "").localizedCaseInsensitiveCompare(rhs.email ?? "")
                    return cmp == .orderedSame ? lhs.id < rhs.id : cmp == .orderedAscending
                case .type, .name:
                    let cmp = sortName(lhs).localizedCaseInsensitiveCompare(sortName(rhs))
                    return cmp == .orderedSame ? lhs.id < rhs.id : cmp == .orderedAscending
                }
            }
            return sortDirection == .ascending ? sorted : sorted.reversed()
        }

        public var isSearchWithoutResults: Bool {
            !searchQuery.trimmed.isEmpty && !users.isEmpty && displayedUsers.isEmpty
        }

        /// Whether the Profile form differs from the loaded user.
        public var isProfileDirty: Bool {
            guard let user = detailUser else { return false }
            return editDisplayName != (user.displayName ?? "")
                || editUsername != user.username
                || editEmail != (user.email ?? "")
        }

        /// Inline error for the Profile email field. The server requires a non empty email and
        /// 409s on a duplicate; the shape check is a client side nicety.
        public var profileEmailError: String? {
            if editEmail.trimmed.isEmpty { return L10n.UserManagement.errorEmailRequired }
            return CredentialRules.isEmailShaped(editEmail) ? nil : L10n.UserManagement.errorEmailInvalid
        }

        /// The server stores a blank username as `null`, which can't decode back, so the form
        /// refuses to submit an empty one.
        public var profileUsernameError: String? {
            editUsername.trimmed.isEmpty ? L10n.UserManagement.errorUsernameRequired : nil
        }

        public var isProfileSaveEnabled: Bool {
            isProfileDirty && !isSavingProfile && profileEmailError == nil && profileUsernameError == nil
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case refreshRequested
        case usersResponse(Result<[User], FilesClientError>)
        case featuresResponse(ServerFeatures)
        case searchQueryChanged(String)
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)

        case userTapped(User.ID)
        case detailDismissed
        case detailTabChanged(DetailTab)
        case volumesResponse(Result<[UserVolume], FilesClientError>)

        case editDisplayNameChanged(String)
        case editUsernameChanged(String)
        case editEmailChanged(String)
        case saveProfileTapped
        case profileResponse(Result<User, FilesClientError>)

        case grantAdminTapped
        case rolesResponse(Result<User, FilesClientError>)

        case deleteUserTapped(User)
        case deleteUserConfirmed
        case deleteUserCancelled
        case deleteUserResponse(User.ID, Result<Bool, FilesClientError>)

        case createUserTapped
        case createSheetDismissed
        case createEmailChanged(String)
        case createUsernameChanged(String)
        case createPasswordChanged(String)
        case createIsAdminChanged(Bool)
        case createSubmitTapped
        case createResponse(Result<User, FilesClientError>)

        case setPasswordTapped
        case passwordSheetDismissed
        case passwordFieldChanged(String)
        case passwordSubmitTapped
        case passwordResponse(Result<Bool, FilesClientError>)

        case addVolumeTapped
        case editVolumeTapped(UserVolume)
        case volumeSheetDismissed
        case volumeLabelChanged(String)
        case volumePathSelected(String)
        case volumeAccessModeChanged(ShareAccessMode)
        case volumeSubmitTapped
        case volumeResponse(Result<UserVolume, FilesClientError>)
        case removeVolumeTapped(UserVolume)
        case removeVolumeConfirmed
        case removeVolumeCancelled
        case removeVolumeResponse(UserVolume.ID, Result<Bool, FilesClientError>)

        case toastDismissed
    }

    @Dependency(\.filesClient) var filesClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.users.isEmpty else { return .none }
                return loadEverything(&state)

            case .refreshRequested:
                return loadEverything(&state)

            case let .usersResponse(.success(users)):
                state.isLoading = false
                state.errorMessage = nil
                state.users = IdentifiedArray(uniqueElements: users)
                if let user = state.detailUser {
                    // Don't stomp edits the admin has typed but not saved; a background reload
                    // (e.g. right after setting a password) would otherwise wipe them.
                    if !state.isProfileDirty {
                        seedProfileForm(&state, from: user)
                    }
                } else if state.detailUserID != nil {
                    // The open user was removed elsewhere, so close the detail.
                    state.detailUserID = nil
                }
                return .none

            case let .usersResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.userMessage
                return .none

            case let .featuresResponse(features):
                state.hasLoadedFeatures = true
                state.isUserVolumesEnabled = features.isUserVolumesEnabled
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

            case let .userTapped(id):
                guard let user = state.users[id: id] else { return .none }
                state.detailUserID = id
                state.detailTab = .profile
                state.detailErrorMessage = nil
                state.volumes = []
                state.hasLoadedVolumesForDetail = false
                seedProfileForm(&state, from: user)
                var effects: [Effect<Action>] = []
                // Recover from a failed initial feature flag load: retry once here so the
                // Volumes tab can still turn up on a detail screen.
                if !state.hasLoadedFeatures {
                    let serverURL = state.serverURL
                    let filesClient = self.filesClient
                    effects.append(.run { send in
                        if let features = try? await filesClient.serverFeatures(serverURL) {
                            await send(.featuresResponse(features))
                        }
                    })
                }
                if state.isUserVolumesEnabled {
                    effects.append(loadVolumes(&state, userID: id))
                }
                return .merge(effects)

            case .detailDismissed:
                state.detailUserID = nil
                state.detailErrorMessage = nil
                state.isSavingProfile = false
                state.isUpdatingRoles = false
                state.isLoadingVolumes = false
                return .merge(
                    .cancel(id: CancelID.userMutation),
                    .cancel(id: CancelID.volumeMutation),
                    .cancel(id: CancelID.volumes)
                )

            case let .detailTabChanged(tab):
                state.detailTab = tab
                if tab == .volumes, state.isUserVolumesEnabled, !state.hasLoadedVolumesForDetail,
                   !state.isLoadingVolumes, let id = state.detailUserID {
                    return loadVolumes(&state, userID: id)
                }
                return .none

            case let .volumesResponse(.success(volumes)):
                state.isLoadingVolumes = false
                state.hasLoadedVolumesForDetail = true
                state.volumes = IdentifiedArray(uniqueElements: volumes)
                return .none

            case let .volumesResponse(.failure(error)):
                state.isLoadingVolumes = false
                state.detailErrorMessage = error.userMessage
                return .none

            case let .editDisplayNameChanged(value):
                state.editDisplayName = value
                return .none

            case let .editUsernameChanged(value):
                state.editUsername = value
                return .none

            case let .editEmailChanged(value):
                state.editEmail = value
                return .none

            case .saveProfileTapped:
                guard let id = state.detailUserID, state.isProfileSaveEnabled else { return .none }
                state.isSavingProfile = true
                state.detailErrorMessage = nil
                let request = UpdateUserRequest(
                    email: state.editEmail.trimmed,
                    username: state.editUsername.trimmed,
                    displayName: state.editDisplayName.trimmed
                )
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.profileResponse(try await apiResult {
                        try await filesClient.updateUser(serverURL, id, request)
                    }))
                }
                .cancellable(id: CancelID.userMutation, cancelInFlight: true)

            case let .profileResponse(.success(user)):
                state.isSavingProfile = false
                state.users[id: user.id] = user
                seedProfileForm(&state, from: user)
                state.toast = L10n.UserManagement.toastProfileUpdated
                return .none

            case let .profileResponse(.failure(error)):
                state.isSavingProfile = false
                state.detailErrorMessage = error.userMessage
                return .none

            case .grantAdminTapped:
                guard let user = state.detailUser, !user.isAdmin, !state.isUpdatingRoles else { return .none }
                state.isUpdatingRoles = true
                state.detailErrorMessage = nil
                let request = UpdateUserRequest(roles: (Set(user.roles).union([UserRole.admin])).sorted())
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                let id = user.id
                return .run { send in
                    await send(.rolesResponse(try await apiResult {
                        try await filesClient.updateUser(serverURL, id, request)
                    }))
                }
                .cancellable(id: CancelID.userMutation, cancelInFlight: true)

            case let .rolesResponse(.success(user)):
                state.isUpdatingRoles = false
                state.users[id: user.id] = user
                state.toast = L10n.UserManagement.toastAdminGranted
                return .none

            case let .rolesResponse(.failure(error)):
                state.isUpdatingRoles = false
                state.detailErrorMessage = error.userMessage
                return .none

            case let .deleteUserTapped(user):
                state.userToDelete = user
                return .none

            case .deleteUserCancelled:
                state.userToDelete = nil
                return .none

            case .deleteUserConfirmed:
                guard let user = state.userToDelete else { return .none }
                state.userToDelete = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.deleteUserResponse(user.id, try await apiResult {
                        try await filesClient.deleteUser(serverURL, user.id)
                        return true
                    }))
                }
                .cancellable(id: CancelID.userMutation, cancelInFlight: true)

            case let .deleteUserResponse(id, .success):
                state.users.remove(id: id)
                if state.detailUserID == id { state.detailUserID = nil }
                state.toast = L10n.UserManagement.toastUserRemoved
                return .none

            case let .deleteUserResponse(_, .failure(error)):
                // Delete is only reachable from the detail screen's danger zone, so surface it
                // there; the list level `errorMessage` is for load failures.
                state.detailErrorMessage = error.userMessage
                return .none

            case .createUserTapped:
                state.createSheet = CreateUserState()
                return .none

            case .createSheetDismissed:
                state.createSheet = nil
                return .none

            case let .createEmailChanged(value):
                state.createSheet?.email = value
                return .none

            case let .createUsernameChanged(value):
                state.createSheet?.username = value
                return .none

            case let .createPasswordChanged(value):
                state.createSheet?.password = value
                return .none

            case let .createIsAdminChanged(value):
                state.createSheet?.isAdmin = value
                return .none

            case .createSubmitTapped:
                guard let sheet = state.createSheet, sheet.isSubmitEnabled else { return .none }
                state.createSheet?.isSubmitting = true
                state.createSheet?.errorMessage = nil
                let request = CreateUserRequest(
                    email: sheet.email.trimmed,
                    username: sheet.username.trimmed.isEmpty ? nil : sheet.username.trimmed,
                    password: sheet.password,
                    isAdmin: sheet.isAdmin
                )
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.createResponse(try await apiResult {
                        try await filesClient.createUser(serverURL, request)
                    }))
                }
                .cancellable(id: CancelID.createUser, cancelInFlight: true)

            case let .createResponse(.success(user)):
                state.createSheet = nil
                state.users.append(user)
                state.toast = L10n.UserManagement.toastUserCreated
                return .none

            case let .createResponse(.failure(error)):
                state.createSheet?.isSubmitting = false
                state.createSheet?.errorMessage = error.userMessage
                return .none

            case .setPasswordTapped:
                guard let user = state.detailUser else { return .none }
                state.passwordSheet = PasswordSheetState(
                    userID: user.id,
                    userLabel: user.displayName ?? user.username,
                    hasExistingPassword: user.hasLocalPassword
                )
                return .none

            case .passwordSheetDismissed:
                state.passwordSheet = nil
                return .none

            case let .passwordFieldChanged(value):
                state.passwordSheet?.password = value
                return .none

            case .passwordSubmitTapped:
                guard let sheet = state.passwordSheet, sheet.isSubmitEnabled else { return .none }
                state.passwordSheet?.isSubmitting = true
                state.passwordSheet?.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                let userID = sheet.userID
                let password = sheet.password
                return .run { send in
                    await send(.passwordResponse(try await apiResult {
                        try await filesClient.setUserPassword(serverURL, userID, password)
                        return true
                    }))
                }
                .cancellable(id: CancelID.setPassword, cancelInFlight: true)

            case .passwordResponse(.success):
                state.passwordSheet = nil
                state.toast = L10n.UserManagement.toastPasswordUpdated
                return reloadUsers(&state)

            case let .passwordResponse(.failure(error)):
                state.passwordSheet?.isSubmitting = false
                state.passwordSheet?.errorMessage = error.userMessage
                return .none

            case .addVolumeTapped:
                guard let id = state.detailUserID else { return .none }
                state.volumeSheet = VolumeSheetState(userID: id)
                return .none

            case let .editVolumeTapped(volume):
                state.volumeSheet = VolumeSheetState(
                    userID: volume.userId,
                    editingVolumeID: volume.id,
                    label: volume.label,
                    selectedPath: volume.path,
                    accessMode: volume.accessMode
                )
                return .none

            case .volumeSheetDismissed:
                state.volumeSheet = nil
                return .none

            case let .volumeLabelChanged(value):
                state.volumeSheet?.label = value
                return .none

            case let .volumePathSelected(path):
                state.volumeSheet?.selectedPath = path
                if state.volumeSheet?.label.trimmed.isEmpty == true {
                    state.volumeSheet?.label = (path as NSString).lastPathComponent
                }
                return .none

            case let .volumeAccessModeChanged(mode):
                state.volumeSheet?.accessMode = mode
                return .none

            case .volumeSubmitTapped:
                guard let sheet = state.volumeSheet, sheet.isSubmitEnabled else { return .none }
                state.volumeSheet?.isSubmitting = true
                state.volumeSheet?.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                let userID = sheet.userID
                let label = sheet.label.trimmed
                let path = sheet.selectedPath.trimmed
                let mode = sheet.accessMode
                let editingID = sheet.editingVolumeID
                return .run { send in
                    await send(.volumeResponse(try await apiResult {
                        if let editingID {
                            return try await filesClient.updateUserVolume(serverURL, userID, editingID, label, mode)
                        }
                        return try await filesClient.addUserVolume(
                            serverURL, userID, AddUserVolumeRequest(label: label, path: path, accessMode: mode)
                        )
                    }))
                }
                .cancellable(id: CancelID.volumeMutation, cancelInFlight: true)

            case let .volumeResponse(.success(volume)):
                state.volumeSheet = nil
                state.volumes[id: volume.id] = volume
                state.toast = L10n.UserManagement.toastVolumeSaved
                return .none

            case let .volumeResponse(.failure(error)):
                state.volumeSheet?.isSubmitting = false
                state.volumeSheet?.errorMessage = error.userMessage
                return .none

            case let .removeVolumeTapped(volume):
                state.volumeToRemove = volume
                return .none

            case .removeVolumeCancelled:
                state.volumeToRemove = nil
                return .none

            case .removeVolumeConfirmed:
                guard let volume = state.volumeToRemove else { return .none }
                state.volumeToRemove = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.removeVolumeResponse(volume.id, try await apiResult {
                        try await filesClient.removeUserVolume(serverURL, volume.userId, volume.id)
                        return true
                    }))
                }
                .cancellable(id: CancelID.volumeMutation, cancelInFlight: true)

            case let .removeVolumeResponse(id, .success):
                state.volumes.remove(id: id)
                state.toast = L10n.UserManagement.toastVolumeRemoved
                return .none

            case let .removeVolumeResponse(_, .failure(error)):
                state.detailErrorMessage = error.userMessage
                return .none

            case .toastDismissed:
                state.toast = nil
                return .none
            }
        }
    }

    // MARK: Effects

    private func loadEverything(_ state: inout State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        state.isLoading = state.users.isEmpty
        state.errorMessage = nil
        // Sequential, not `.merge`: the users list is the payload, the feature flag is a best
        // effort nicety that only gates a tab. Ordering also keeps the tests deterministic.
        return .run { send in
            await send(.usersResponse(try await apiResult {
                try await filesClient.listUsers(serverURL)
            }))
            if let features = try? await filesClient.serverFeatures(serverURL) {
                await send(.featuresResponse(features))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private func reloadUsers(_ state: inout State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.usersResponse(try await apiResult {
                try await filesClient.listUsers(serverURL)
            }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private func loadVolumes(_ state: inout State, userID: String) -> Effect<Action> {
        state.isLoadingVolumes = true
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.volumesResponse(try await apiResult {
                try await filesClient.userVolumes(serverURL, userID)
            }))
        }
        .cancellable(id: CancelID.volumes, cancelInFlight: true)
    }

    private func seedProfileForm(_ state: inout State, from user: User) {
        state.editDisplayName = user.displayName ?? ""
        state.editUsername = user.username
        state.editEmail = user.email ?? ""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The name the list sorts and groups by: the display name if the server has one, else the
/// username, which is always present.
private func sortName(_ user: User) -> String {
    user.displayName ?? user.username
}
