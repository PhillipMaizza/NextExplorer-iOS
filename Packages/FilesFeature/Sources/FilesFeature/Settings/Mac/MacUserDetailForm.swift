#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = 48
        static let headerSpacing: CGFloat = .space12
    }

    /// One user's settings on the Mac: profile and sign in options together in a single form
    /// (iOS splits them into tabs), then their volumes, then removing them.
    struct MacUserDetailForm: View {
        @Bindable var store: StoreOf<UserManagementFeature>
        let user: User

        var body: some View {
            MacSettingsPane {
                Section {
                    header
                }
                profileSection
                signInSection
                if store.isUserVolumesEnabled {
                    volumesSection
                }
                if !store.isViewingOwnAccount {
                    Section {
                        LabeledContent(L10n.UserDetail.dangerZoneTitle) {
                            Button(L10n.UserDetail.dangerZoneRemoveUser + "…", role: .destructive) {
                                store.send(.deleteUserTapped(user))
                            }
                        }
                    } footer: {
                        MacSectionFooter(L10n.UserDetail.dangerZoneSubtitle)
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
        }

        private var profileSection: some View {
            Section(L10n.UserDetail.sectionGeneralInfo) {
                field(L10n.UserDetail.profileDisplayNameField, prompt: L10n.UserDetail.profileDisplayNamePlaceholder, \.editDisplayName, UserManagementFeature.Action.editDisplayNameChanged)
                field(L10n.UserDetail.profileUsernameField, prompt: L10n.UserDetail.profileUsernamePlaceholder, \.editUsername, UserManagementFeature.Action.editUsernameChanged)
                if store.isProfileDirty, let error = store.profileUsernameError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
                field(L10n.UserDetail.profileEmailField, prompt: L10n.UserDetail.profileEmailPlaceholder, \.editEmail, UserManagementFeature.Action.editEmailChanged)
                if store.isProfileDirty, let error = store.profileEmailError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
                if let error = store.detailErrorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
                HStack {
                    Spacer()
                    if store.isSavingProfile {
                        MacSpinner()
                    }
                    Button(L10n.UserDetail.profileSave) { store.send(.saveProfileTapped) }
                        .disabled(!store.isProfileSaveEnabled)
                }
            }
        }

        private var signInSection: some View {
            Section(L10n.UserDetail.sectionRoles) {
                LabeledContent {
                    if store.isUpdatingRoles {
                        MacSpinner()
                    } else if !user.isAdmin {
                        Button(L10n.UserDetail.roleGrantAdmin) { store.send(.grantAdminTapped) }
                    }
                } label: {
                    // The backend refuses to demote an administrator, so there is no revoke.
                    MacRowTitle(
                        title: L10n.UserDetail.roleAdmin,
                        subtitle: user.isAdmin ? L10n.UserDetail.roleAdminLocked : L10n.UserDetail.roleAdminSubtitle
                    )
                }
                LabeledContent {
                    Button((user.hasLocalPassword ? L10n.UserDetail.passwordReset : L10n.UserDetail.passwordSet) + "…") {
                        store.send(.setPasswordTapped)
                    }
                } label: {
                    MacRowTitle(
                        title: L10n.UserDetail.sectionLocalPassword,
                        subtitle: user.hasLocalPassword ? L10n.UserDetail.passwordHasLocal : L10n.UserDetail.passwordSSOOnly
                    )
                }
                LabeledContent(L10n.UserDetail.sectionSSO) {
                    if user.oidcMethods.isEmpty {
                        Text(L10n.UserDetail.ssoNone)
                    } else {
                        VStack(alignment: .trailing) {
                            ForEach(Array(user.oidcMethods.enumerated()), id: \.offset) { _, method in
                                HStack {
                                    Text(method.provider ?? L10n.UserDetail.ssoBadge)
                                    Text(L10n.UserDetail.ssoLinked).foregroundStyle(Color.positiveText)
                                }
                            }
                        }
                    }
                }
            }
        }

        private var volumesSection: some View {
            Section {
                if store.volumesPhase == .loading {
                    MacSpinner()
                } else if store.volumes.isEmpty {
                    Text(L10n.UserDetail.volumesNone).foregroundStyle(.secondary)
                } else {
                    ForEach(store.volumes) { volume in
                        LabeledContent {
                            HStack {
                                AccessModeBadge(mode: volume.accessMode).fixedSize()
                                Button(L10n.Common.edit + "…") { store.send(.editVolumeTapped(volume)) }
                                    .accessibilityLabel(L10n.UserDetail.volumeEditAccessibility(volume.label))
                                Button(L10n.Common.remove + "…") { store.send(.removeVolumeTapped(volume)) }
                                    .accessibilityLabel(L10n.UserDetail.volumeRemoveAccessibility(volume.label))
                            }
                        } label: {
                            MacRowTitle(title: volume.label, subtitle: volume.path)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(L10n.UserDetail.volumesAssign + "…") { store.send(.addVolumeTapped) }
                }
            } header: {
                Text(L10n.UserDetail.sectionAssignedVolumes)
            } footer: {
                MacSectionFooter(L10n.UserDetail.volumesFootnote)
            }
        }

        private func field(
            _ title: String,
            prompt: String,
            _ keyPath: KeyPath<UserManagementFeature.State, String>,
            _ action: @escaping @Sendable (String) -> UserManagementFeature.Action
        ) -> some View {
            TextField(title, text: Binding(get: { store.state[keyPath: keyPath] }, set: { store.send(action($0)) }), prompt: Text(prompt))
                .autocorrectionDisabled()
        }
    }

    #Preview("User") {
        var state = UserManagementFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), currentUserID: "u1")
        state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
        state.phase = .loaded
        let user = User.previewManagedUsers.last ?? User(id: "u2", username: "jane", email: "jane@example.com")
        return MacUserDetailForm(store: Store(initialState: state) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue }, user: user)
            .previewCanvas(.settingsPane)
    }
#endif
