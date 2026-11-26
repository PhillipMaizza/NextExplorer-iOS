#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = .size40
        static let fieldWidth: CGFloat = 300
        static let tallRowHeight: CGFloat = .size64
        static let accountActionWidth: CGFloat = 140
    }

    struct MacUserDetailForm: View {
        @Bindable var store: StoreOf<UserManagementFeature>
        let user: User

        private var tabs: [UserManagementFeature.DetailTab] {
            UserManagementFeature.DetailTab.allCases.filter { $0 != .volumes || store.isUserVolumesEnabled }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                header
                switch store.detailTab {
                case .profile: profileTab
                case .security: securityTab
                case .volumes: volumesTab
                }
                if let error = store.detailErrorMessage {
                    MacNote(error, kind: .error)
                }
            }
        }

        private var header: some View {
            HStack(spacing: .space12) {
                AvatarView.person(user.displayLabel, size: Metrics.avatarSize)
                MacFormRowTitle(title: user.displayLabel, subtitle: user.email ?? "")
                Spacer(minLength: .space16)
                MacSegmentedPicker(
                    L10n.UserManagement.tabProfile,
                    options: tabs,
                    selection: Binding(get: { store.detailTab }, set: { store.send(.detailTabChanged($0)) })
                ) { $0.title }
            }
            .padding(.horizontal, .space4)
        }

        private var profileTab: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup {
                    profileFieldRows
                }
                profileNotes
                HStack {
                    Spacer(minLength: .zero)
                    MacPaneSaveButton(
                        title: L10n.UserDetail.profileSave,
                        isSaving: store.isSavingProfile,
                        isEnabled: store.isProfileSaveEnabled
                    ) { store.send(.saveProfileTapped) }
                }
                MacFormGroup {
                    accountRows
                }
                .padding(.top, .space8)
            }
        }

        @ViewBuilder
        private var profileFieldRows: some View {
            profileField(
                L10n.UserDetail.profileDisplayNameField,
                prompt: L10n.UserDetail.profileDisplayNamePlaceholder,
                \.editDisplayName,
                UserManagementFeature.Action.editDisplayNameChanged
            )
            profileField(
                L10n.UserDetail.profileUsernameField,
                prompt: L10n.UserDetail.profileUsernamePlaceholder,
                \.editUsername,
                UserManagementFeature.Action.editUsernameChanged
            )
            profileField(
                L10n.UserDetail.profileEmailField,
                prompt: L10n.UserDetail.profileEmailPlaceholder,
                \.editEmail,
                UserManagementFeature.Action.editEmailChanged
            )
        }

        @ViewBuilder
        private var accountRows: some View {
            MacFormRow {
                MacFormRowTitle(
                    title: L10n.UserDetail.roleAdmin,
                    subtitle: user.isAdmin ? L10n.UserDetail.roleAdminLocked : L10n.UserDetail.roleAdminSubtitle
                )
            } control: {
                if store.isUpdatingRoles {
                    MacSpinner()
                } else if !user.isAdmin {
                    Button { store.send(.grantAdminTapped) } label: {
                        accountActionLabel(L10n.UserDetail.roleGrantAdmin, icon: IconKit.shield)
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                }
            }
            .frame(minHeight: Metrics.tallRowHeight)
            if !store.isViewingOwnAccount {
                MacFormRow {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(L10n.UserDetail.dangerZoneTitle)
                            .foregroundStyle(Color.negativeText)
                        Text(L10n.UserDetail.dangerZoneSubtitle)
                            .type(.body3(.regular), style: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } control: {
                    Button(role: .destructive) { store.send(.deleteUserTapped(user)) } label: {
                        accountActionLabel(L10n.UserDetail.dangerZoneRemoveUser, icon: IconKit.delete)
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                }
                .frame(minHeight: Metrics.tallRowHeight)
            }
        }

        private func accountActionLabel(_ title: String, icon: Image) -> some View {
            Label { Text(title) } icon: { icon }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: Metrics.accountActionWidth)
        }

        private var securityTab: some View {
            VStack(alignment: .leading, spacing: .space16) {
                MacFormGroup(L10n.UserDetail.sectionLocalPassword) {
                    MacFormRow {
                        Text(user.hasLocalPassword ? L10n.UserDetail.passwordHasLocal : L10n.UserDetail.passwordSSOOnly)
                            .fixedSize(horizontal: false, vertical: true)
                    } control: {
                        Button(L10n.ellipsized(user.hasLocalPassword
                                ? L10n.UserDetail.passwordReset
                                : L10n.UserDetail.passwordSet))
                        {
                            store.send(.setPasswordTapped)
                        }
                        .buttonStyle(.macDS(.secondary, size: .small))
                    }
                }
                let recoveryRows = store.isViewingOwnAccount ? [] : UserRecoveryRow.rows(for: user)
                if !recoveryRows.isEmpty {
                    MacFormGroup(L10n.UserDetail.sectionAccountRecovery) {
                        ForEach(recoveryRows) { row in
                            MacFormRow {
                                MacFormRowTitle(title: row.title, subtitle: row.subtitle)
                            } control: {
                                Button(
                                    row.reset.actionTitle,
                                    role: row.reset == .passkeys
                                        ? .destructive
                                        : nil
                                ) {
                                    store.send(.securityResetTapped(row.reset))
                                }
                                .buttonStyle(.macDS(.secondary, size: .small))
                                .disabled(store.isResettingSecurity)
                            }
                            .frame(minHeight: Metrics.tallRowHeight)
                        }
                    }
                }
                MacFormGroup(L10n.UserDetail.sectionSSO) {
                    MacFormRow {
                        if user.oidcMethods.isEmpty {
                            Text(L10n.UserDetail.ssoNone)
                        } else {
                            HStack(spacing: .space8) {
                                ForEach(Array(user.oidcMethods.enumerated()), id: \.offset) { _, method in
                                    MacChip(text: method.provider ?? L10n.UserDetail.ssoBadge, tone: .green)
                                }
                            }
                        }
                    } control: {
                        EmptyView()
                    }
                }
            }
        }

        private var volumesTab: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(L10n.UserDetail.sectionAssignedVolumes) {
                    if store.volumesPhase == .loading {
                        MacFormRow {
                            MacSpinner()
                        } control: {
                            EmptyView()
                        }
                    } else if store.volumes.isEmpty {
                        MacFormRow {
                            Text(L10n.UserDetail.volumesNone).foregroundStyle(Color.macChromeSecondary)
                        } control: {
                            EmptyView()
                        }
                    }
                    ForEach(store.volumes) { volume in
                        volumeRow(volume)
                    }
                }
                MacFormFootnote(L10n.UserDetail.volumesFootnote)
                Button(L10n.ellipsized(L10n.UserDetail.volumesAssign)) { store.send(.addVolumeTapped) }
                    .buttonStyle(.macDS(.primary, size: .small))
                    .padding(.top, .space8)
            }
        }

        private func volumeRow(_ volume: UserVolume) -> some View {
            MacFormRow {
                HStack(spacing: .space12) {
                    MacItemIcon(kind: "", isDirectory: true)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(volume.label)
                        Text(volume.path)
                            .type(.body3(.regular), style: .secondary)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } control: {
                HStack(spacing: .space8) {
                    MacChip(
                        text: volume.accessMode == .readonly ? L10n.AccessMode.readonly : L10n.AccessMode.readwrite,
                        tone: volume.accessMode == .readonly ? .gray : .green
                    )
                    Button(L10n.Common.edit) { store.send(.editVolumeTapped(volume)) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .accessibilityLabel(L10n.UserDetail.volumeEditAccessibility(volume.label))
                    Button(L10n.Common.remove, role: .destructive) { store.send(.removeVolumeTapped(volume)) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .accessibilityLabel(L10n.UserDetail.volumeRemoveAccessibility(volume.label))
                }
            }
            .frame(minHeight: Metrics.tallRowHeight)
        }

        @ViewBuilder
        private var profileNotes: some View {
            if store.isProfileDirty, let error = store.profileUsernameError {
                MacNote(error, kind: .error)
            }
            if store.isProfileDirty, let error = store.profileEmailError {
                MacNote(error, kind: .error)
            }
        }

        private func profileField(
            _ title: String,
            prompt: String,
            _ keyPath: KeyPath<UserManagementFeature.State, String>,
            _ action: @escaping @Sendable (String) -> UserManagementFeature.Action
        ) -> some View {
            MacFormRow(title) {
                field(title, prompt: prompt, keyPath, action)
                    .frame(width: Metrics.fieldWidth)
            }
        }

        private func field(
            _ title: String,
            prompt: String,
            _ keyPath: KeyPath<UserManagementFeature.State, String>,
            _ action: @escaping @Sendable (String) -> UserManagementFeature.Action
        ) -> some View {
            MacTextField(
                title,
                text: Binding(get: { store.state[keyPath: keyPath] }, set: { store.send(action($0)) }),
                prompt: prompt
            )
            .autocorrectionDisabled()
        }
    }

    @MainActor
    private func userDetailPreview(_ tab: UserManagementFeature.DetailTab) -> some View {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
        state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
        state.phase = .loaded
        state.isUserVolumesEnabled = true
        state.detailTab = tab
        state.volumesPhase = .loaded
        let user = User.previewManagedUsers.last ?? User(id: "u2", username: "jane", email: "jane@example.com")
        state.detailUserID = user.id
        state.editDisplayName = user.displayLabel
        state.editEmail = user.email ?? ""
        state.volumes = [UserVolume(
            id: "v1",
            userId: user.id,
            label: "Media",
            path: "/mnt/media",
            accessMode: .readonly
        )]
        return MacUserDetailForm(store: Store(initialState: state) { EmptyReducer() }, user: user)
            .padding(.space32)
            .previewCanvasWidth(.table)
            .background(Color.macCard)
    }

    #Preview("Profile") {
        userDetailPreview(.profile)
    }

    #Preview("Security") {
        userDetailPreview(.security)
    }

    #Preview("Volumes") {
        userDetailPreview(.volumes)
    }
#endif
