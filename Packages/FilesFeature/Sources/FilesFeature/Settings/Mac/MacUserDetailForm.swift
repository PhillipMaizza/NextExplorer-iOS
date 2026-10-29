#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = 56
        static let fieldWidth: CGFloat = 260
        static let headerSpacing: CGFloat = .space12
        static let headerPadding: CGFloat = .space24
    }

    /// One user's settings on the Mac: profile and sign in options together in a single form
    /// (iOS splits them into tabs), then their volumes, then removing them.
    struct MacUserDetailForm: View {
        @Bindable var store: StoreOf<UserManagementFeature>
        let user: User

        var body: some View {
            VStack(spacing: 0) {
                header
                MacSettingsForm {
                    profileRows
                    signInRows
                    if store.isUserVolumesEnabled {
                        volumeRows
                    }
                    if !store.isViewingOwnAccount {
                        MacSettingsRow(L10n.UserDetail.dangerZoneTitle) {
                            Button(L10n.UserDetail.dangerZoneRemoveUser + "…", role: .destructive) {
                                store.send(.deleteUserTapped(user))
                            }
                            MacSettingsNote(L10n.UserDetail.dangerZoneSubtitle)
                        }
                    }
                }
            }
        }

        private var header: some View {
            HStack(spacing: Metrics.headerSpacing) {
                AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)
                VStack(alignment: .leading) {
                    Text(user.displayName ?? user.username)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let email = user.email {
                        Text(email).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
            }
            .padding([.horizontal, .top], Metrics.headerPadding)
        }

        @ViewBuilder
        private var profileRows: some View {
            MacSettingsRow(L10n.UserDetail.profileDisplayNameField) {
                field(L10n.UserDetail.profileDisplayNamePlaceholder, \.editDisplayName, UserManagementFeature.Action.editDisplayNameChanged)
            }
            MacSettingsRow(L10n.UserDetail.profileUsernameField) {
                field(L10n.UserDetail.profileUsernamePlaceholder, \.editUsername, UserManagementFeature.Action.editUsernameChanged)
                if store.isProfileDirty, let error = store.profileUsernameError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            MacSettingsRow(L10n.UserDetail.profileEmailField) {
                field(L10n.UserDetail.profileEmailPlaceholder, \.editEmail, UserManagementFeature.Action.editEmailChanged)
                if store.isProfileDirty, let error = store.profileEmailError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
                HStack {
                    Button(L10n.UserDetail.profileSave) { store.send(.saveProfileTapped) }
                        .disabled(!store.isProfileSaveEnabled)
                    if store.isSavingProfile {
                        ProgressView().controlSize(.small)
                    }
                }
                if let error = store.detailErrorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            MacSettingsRow(L10n.UserDetail.sectionRoles) {
                if store.isUpdatingRoles {
                    ProgressView().controlSize(.small)
                } else if user.isAdmin {
                    Text(L10n.UserDetail.roleAdmin)
                    // The backend refuses to demote an administrator, so there is no revoke.
                    MacSettingsNote(L10n.UserDetail.roleAdminLocked)
                } else {
                    Button(L10n.UserDetail.roleGrantAdmin) { store.send(.grantAdminTapped) }
                    MacSettingsNote(L10n.UserDetail.roleAdminSubtitle)
                }
            }
        }

        @ViewBuilder
        private var signInRows: some View {
            MacSettingsRow(L10n.UserDetail.sectionLocalPassword) {
                Text(user.hasLocalPassword ? L10n.UserDetail.passwordHasLocal : L10n.UserDetail.passwordSSOOnly)
                Button((user.hasLocalPassword ? L10n.UserDetail.passwordReset : L10n.UserDetail.passwordSet) + "…") {
                    store.send(.setPasswordTapped)
                }
            }
            MacSettingsRow(L10n.UserDetail.sectionSSO) {
                if user.oidcMethods.isEmpty {
                    Text(L10n.UserDetail.ssoNone).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(user.oidcMethods.enumerated()), id: \.offset) { _, method in
                        HStack {
                            Text(method.provider ?? L10n.UserDetail.ssoBadge)
                            Text(L10n.UserDetail.ssoLinked).foregroundStyle(Color.positiveText)
                        }
                    }
                }
            }
        }

        private var volumeRows: some View {
            MacSettingsRow(L10n.UserDetail.sectionAssignedVolumes) {
                if store.volumesPhase == .loading {
                    ProgressView().controlSize(.small)
                } else if store.volumes.isEmpty {
                    Text(L10n.UserDetail.volumesNone).foregroundStyle(.secondary)
                } else {
                    ForEach(store.volumes) { volume in
                        VStack(alignment: .leading, spacing: .space4) {
                            HStack {
                                Text(volume.label).lineLimit(1)
                                AccessModeBadge(mode: volume.accessMode).fixedSize()
                            }
                            Text(volume.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            HStack {
                                Button(L10n.Common.edit + "…") { store.send(.editVolumeTapped(volume)) }
                                    .accessibilityLabel(L10n.UserDetail.volumeEditAccessibility(volume.label))
                                Button(L10n.Common.remove + "…") { store.send(.removeVolumeTapped(volume)) }
                                    .accessibilityLabel(L10n.UserDetail.volumeRemoveAccessibility(volume.label))
                            }
                            .controlSize(.small)
                        }
                        .padding(.bottom, .space4)
                    }
                }
                Button(L10n.UserDetail.volumesAssign + "…") { store.send(.addVolumeTapped) }
                MacSettingsNote(L10n.UserDetail.volumesFootnote)
            }
        }

        private func field(
            _ prompt: String,
            _ keyPath: KeyPath<UserManagementFeature.State, String>,
            _ action: @escaping @Sendable (String) -> UserManagementFeature.Action
        ) -> some View {
            TextField(prompt, text: Binding(get: { store.state[keyPath: keyPath] }, set: { store.send(action($0)) }), prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .frame(maxWidth: Metrics.fieldWidth)
        }
    }
#endif
