import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Metrics {
    static let avatarSize: CGFloat = .size56
    static let contentSpacing: CGFloat = .space24
    static let cardSpacing: CGFloat = .space12
    static let cardTitleSpacing: CGFloat = .space8
    static let cardPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusCard
    static let horizontalPadding: CGFloat = .space16
    static let rowIconSize: CGFloat = .iconSmall
    static let badgeHorizontalPadding: CGFloat = .space8
    static let badgeVerticalPadding: CGFloat = .space2
}

/// The admin user detail screen (web `UserDetail`). Pushed onto the Settings navigation
/// stack by `UserManagementView`. Profile, Security and Volumes tabs, the last only with the
/// `USER_VOLUMES` feature.
struct UserDetailView: View {
    @Bindable var store: StoreOf<UserManagementFeature>

    private var tabs: [UserManagementFeature.DetailTab] {
        store.isUserVolumesEnabled ? UserManagementFeature.DetailTab.allCases : [.profile, .security]
    }

    var body: some View {
        ScrollView {
            if let user = store.detailUser {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    header(user)

                    if let error = store.detailErrorMessage {
                        ErrorBanner(text: error)
                    }

                    DSSegmentedControl(
                        options: tabs,
                        selection: Binding(
                            get: { store.detailTab },
                            set: { store.send(.detailTabChanged($0)) }
                        ),
                        label: { $0.title }
                    )

                    switch store.detailTab {
                    case .profile:
                        profileTab(user)
                    case .security:
                        securityTab(user)
                    case .volumes:
                        volumesTab
                    }
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.contentSpacing)
            }
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(store.detailUser?.displayName ?? store.detailUser?.username ?? L10n.UserDetail.fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: volumeSheetPresented) {
            VolumeAssignSheet(store: store)
        }
        .alert(
            L10n.UserDetail.removeVolumeTitle,
            isPresented: removeVolumeAlertPresented,
            presenting: store.volumeToRemove
        ) { _ in
            Button(L10n.Common.remove, role: .destructive) { store.send(.removeVolumeConfirmed) }
            Button(L10n.Common.cancel, role: .cancel) { store.send(.removeVolumeCancelled) }
        } message: { volume in
            Text(L10n.UserDetail.removeVolumeMessage(volume.label))
        }
        .alert(
            L10n.UserDetail.removeUserTitle,
            isPresented: deleteAlertPresented,
            presenting: store.userToDelete
        ) { _ in
            Button(L10n.Common.remove, role: .destructive) { store.send(.deleteUserConfirmed) }
            Button(L10n.Common.cancel, role: .cancel) { store.send(.deleteUserCancelled) }
        } message: { user in
            Text(L10n.UserDetail.removeUserMessage(user.displayName ?? user.username))
        }
    }

    // MARK: Header

    private func header(_ user: User) -> some View {
        HStack(spacing: Metrics.cardSpacing) {
            AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)
            VStack(alignment: .leading, spacing: .space2) {
                HStack(spacing: .space8) {
                    Text(user.displayName ?? user.username)
                        .type(.headline3, style: .primary(for: .label))
                        .lineLimit(1)
                    if user.isAdmin { AdminTag() }
                }
                if let email = user.email {
                    Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Profile tab

    @ViewBuilder
    private func profileTab(_ user: User) -> some View {
        Card(L10n.UserDetail.sectionGeneralInfo) {
            LabeledField(L10n.UserDetail.profileDisplayNameField) {
                DSTextField(L10n.UserDetail.profileDisplayNamePlaceholder, text: binding(\.editDisplayName, UserManagementFeature.Action.editDisplayNameChanged))
                    .autocorrectionDisabled()
            }
            LabeledField(L10n.UserDetail.profileUsernameField, error: store.isProfileDirty ? store.profileUsernameError : nil) {
                DSTextField(L10n.UserDetail.profileUsernamePlaceholder, text: binding(\.editUsername, UserManagementFeature.Action.editUsernameChanged))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledField(L10n.UserDetail.profileEmailField, error: store.isProfileDirty ? store.profileEmailError : nil) {
                DSTextField(L10n.UserDetail.profileEmailPlaceholder, text: binding(\.editEmail, UserManagementFeature.Action.editEmailChanged))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            DSButton(L10n.UserDetail.profileSave, style: .primary, isLoading: store.isSavingProfile) {
                store.send(.saveProfileTapped)
            }
            .disabled(!store.isProfileSaveEnabled)
            .padding(.top, .space4)
        }

        Card(L10n.UserDetail.sectionRoles) {
            HStack(alignment: .top, spacing: .space8) {
                IconKit.shield
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    .padding(.top, .space2)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.UserDetail.roleAdmin).type(.body2(.semibold), style: .primary(for: .label))
                    Text(L10n.UserDetail.roleAdminSubtitle)
                        .type(.body3(.regular), style: .secondary)
                }
                Spacer(minLength: .space8)
            }
            if store.isUpdatingRoles {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if user.isAdmin {
                // No "Revoke Admin": the backend refuses to demote any administrator
                // (`PATCH /api/users/:id` 400s with "Demotion of admin is not allowed."), so
                // offering the action would only ever produce an error.
                Text(L10n.UserDetail.roleAdminLocked)
                    .type(.caption(.regular), style: .tertiary)
            } else {
                DSButton(L10n.UserDetail.roleGrantAdmin, style: .secondary) { store.send(.grantAdminTapped) }
            }
        }

        if !store.isViewingOwnAccount {
            dangerZone(user)
        }
    }

    private func dangerZone(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            Text(L10n.UserDetail.dangerZoneTitle).type(.body2(.semibold), style: .error)
            Text(L10n.UserDetail.dangerZoneSubtitle)
                .type(.body3(.regular), style: .secondary)
            DSButton(L10n.UserDetail.dangerZoneRemoveUser, icon: IconKit.delete, style: .failure) {
                store.send(.deleteUserTapped(user))
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.negative.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .strokeBorder(Color.negative.opacity(0.3), lineWidth: .borderWidthHairline)
        )
    }

    // MARK: Security tab

    @ViewBuilder
    private func securityTab(_ user: User) -> some View {
        Card(L10n.UserDetail.sectionLocalPassword) {
            HStack(alignment: .top, spacing: .space8) {
                IconKit.key
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    .padding(.top, .space2)
                Text(user.hasLocalPassword
                    ? L10n.UserDetail.passwordHasLocal
                    : L10n.UserDetail.passwordSSOOnly)
                    .type(.body3(.regular), style: .secondary)
                Spacer(minLength: .space8)
            }
            DSButton(user.hasLocalPassword ? L10n.UserDetail.passwordReset : L10n.UserDetail.passwordSet, style: .secondary) {
                store.send(.setPasswordTapped)
            }
        }

        Card(L10n.UserDetail.sectionSSO) {
            if user.oidcMethods.isEmpty {
                HStack(spacing: .space8) {
                    IconKit.cloud
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.tertiaryDS)
                        .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    Text(L10n.UserDetail.ssoNone).type(.body3(.regular), style: .secondary)
                }
            } else {
                ForEach(Array(user.oidcMethods.enumerated()), id: \.offset) { _, method in
                    HStack(spacing: .space8) {
                        IconKit.cloud
                            .resizable().scaledToFit()
                            .foregroundStyle(Color.secondaryDS)
                            .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        Text(method.provider ?? L10n.UserDetail.ssoBadge).type(.body2(.regular), style: .primary(for: .label))
                        Spacer()
                        Text(L10n.UserDetail.ssoLinked).type(.caption(.semibold), style: .success)
                    }
                }
            }
        }
    }

    // MARK: Volumes tab

    @ViewBuilder
    private var volumesTab: some View {
        Card(L10n.UserDetail.sectionAssignedVolumes) {
            if store.isLoadingVolumes {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.vertical, .space8)
            } else if store.volumes.isEmpty {
                VStack(spacing: .space4) {
                    Text(L10n.UserDetail.volumesNone).type(.body3(.regular), style: .secondary)
                    Text(L10n.UserDetail.volumesNoneSubtitle).type(.caption(.regular), style: .tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, .space8)
            } else {
                ForEach(store.volumes) { volume in
                    volumeRow(volume)
                }
            }
            DSButton(L10n.UserDetail.volumesAssign, icon: IconKit.plus, style: .secondary) {
                store.send(.addVolumeTapped)
            }
            .padding(.top, .space4)
        }

        Text(L10n.UserDetail.volumesFootnote)
            .type(.body3(.regular), style: .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.cardPadding)
            .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.accent.opacity(0.08)))
    }

    private func volumeRow(_ volume: UserVolume) -> some View {
        HStack(spacing: .space12) {
            IconKit.folder
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(volume.label).type(.body2(.semibold), style: .primary(for: .label)).lineLimit(1)
                Text(volume.path).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: .space8)
            AccessModeBadge(mode: volume.accessMode)
            Button { store.send(.editVolumeTapped(volume)) } label: {
                IconKit.rename.resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.UserDetail.volumeEditAccessibility(volume.label))
            Button { store.send(.removeVolumeTapped(volume)) } label: {
                IconKit.delete.resizable().scaledToFit()
                    .foregroundStyle(Color.negative)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.UserDetail.volumeRemoveAccessibility(volume.label))
        }
        .padding(.vertical, .space8)
    }

    // MARK: Helpers

    private func binding(
        _ keyPath: KeyPath<UserManagementFeature.State, String>,
        _ action: @escaping (String) -> UserManagementFeature.Action
    ) -> Binding<String> {
        Binding(get: { store.state[keyPath: keyPath] }, set: { store.send(action($0)) })
    }

    private var volumeSheetPresented: Binding<Bool> {
        Binding(get: { store.volumeSheet != nil }, set: { if !$0 { store.send(.volumeSheetDismissed) } })
    }

    private var removeVolumeAlertPresented: Binding<Bool> {
        Binding(get: { store.volumeToRemove != nil }, set: { if !$0 { store.send(.removeVolumeCancelled) } })
    }

    /// Lives here, not on the list view: the "Remove User" button is in this screen's Danger
    /// Zone, so the confirmation must present over the detail page. Attached to the list it
    /// surfaced one navigation level below, behind the pushed detail.
    private var deleteAlertPresented: Binding<Bool> {
        Binding(get: { store.userToDelete != nil }, set: { if !$0 { store.send(.deleteUserCancelled) } })
    }
}

// MARK: Small pieces

/// A section: an uppercase header over a rounded `backgroundSecondary` box. The header sits
/// outside the box so the tabs read as a list of labelled sections rather than nested titled
/// cards.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardTitleSpacing) {
            Text(title)
                .type(.body3(.semibold), style: .tertiary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                content
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.backgroundSecondary))
        }
    }
}

struct AccessModeBadge: View {
    let mode: ShareAccessMode

    private var tint: Color { mode == .readonly ? .attention : .positive }

    var body: some View {
        Text(mode == .readonly ? L10n.AccessMode.readonly : L10n.AccessMode.readwrite)
            .type(.caption(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Metrics.badgeHorizontalPadding)
            .padding(.vertical, Metrics.badgeVerticalPadding)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

// MARK: Volume assign sheet

private struct VolumeAssignSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.filesClient) private var filesClient

    @State private var listing: AdminDirectoryListing?
    @State private var isBrowsing = false
    @State private var browseError: String?
    /// The directory currently being listed; `nil` is the server's volume root. Bound to a
    /// `.task(id:)` so drilling in or out cancels any in flight listing before the next one,
    /// since rapid taps otherwise race and the slower one wins.
    @State private var browsePath: String?

    private var sheet: UserManagementFeature.VolumeSheetState? { store.volumeSheet }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    if let sheet {
                        if let error = sheet.errorMessage {
                            ErrorBanner(text: error)
                        }

                        LabeledField(L10n.UserDetail.volumeSheetLabelField) {
                            DSTextField(L10n.UserDetail.volumeSheetLabelPlaceholder, text: Binding(
                                get: { store.volumeSheet?.label ?? "" },
                                set: { store.send(.volumeLabelChanged($0)) }
                            ))
                            .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: .space4) {
                            Text(L10n.UserDetail.volumeSheetAccessMode).type(.body3(.semibold), style: .secondary)
                            DSSegmentedControl(
                                options: ShareAccessMode.allCases,
                                selection: Binding(
                                    get: { store.volumeSheet?.accessMode ?? .readwrite },
                                    set: { store.send(.volumeAccessModeChanged($0)) }
                                ),
                                label: { $0.title }
                            )
                        }

                        VStack(alignment: .leading, spacing: .space4) {
                            Text(L10n.UserDetail.volumeSheetDirectory).type(.body3(.semibold), style: .secondary)
                            if sheet.isEditing {
                                Text(sheet.selectedPath)
                                    .type(.body2(.regular))
                                    .foregroundStyle(Color.secondaryDS)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .roundedFieldStyle()
                            } else {
                                directoryBrowser(selectedPath: sheet.selectedPath)
                            }
                        }

                        DSButton(
                            sheet.isEditing ? L10n.UserDetail.volumeSheetSaveEdit : L10n.UserDetail.volumeSheetSaveNew,
                            style: .primary,
                            isLoading: sheet.isSubmitting
                        ) {
                            store.send(.volumeSubmitTapped)
                        }
                        .disabled(!sheet.isSubmitEnabled)
                        .padding(.top, .space4)
                    }
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.contentSpacing)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(sheet?.isEditing == true ? L10n.UserDetail.volumeSheetTitleEdit : L10n.UserDetail.volumeSheetTitleNew)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: browsePath) {
            guard sheet?.isEditing == false else { return }
            await loadDirectories(path: browsePath)
        }
    }

    @ViewBuilder
    private func directoryBrowser(selectedPath: String) -> some View {
        VStack(alignment: .leading, spacing: .space8) {
            if let listing {
                HStack(spacing: .space8) {
                    Text(listing.current).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if let parent = listing.parent {
                        Button {
                            browsePath = parent
                        } label: {
                            IconKit.levelUp.resizable().scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .accessibilityLabel(L10n.UserDetail.directoryPickerGoUp)
                    }
                }
                Button {
                    store.send(.volumePathSelected(listing.current))
                } label: {
                    rowLabel(L10n.UserDetail.directoryPickerUseThis, isSelected: selectedPath == listing.current, icon: IconKit.checkmark)
                }
                .buttonStyle(DSHapticButtonStyle())

                ForEach(listing.directories) { directory in
                    HStack(spacing: .space8) {
                        Button {
                            store.send(.volumePathSelected(directory.path))
                        } label: {
                            rowLabel(directory.name, isSelected: selectedPath == directory.path, icon: IconKit.folder)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        Spacer()
                        Button {
                            browsePath = directory.path
                        } label: {
                            IconKit.chevronRight.resizable().scaledToFit()
                                .foregroundStyle(Color.tertiaryDS)
                                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .accessibilityLabel(L10n.UserDetail.directoryPickerOpen(directory.name))
                    }
                }
            } else if isBrowsing {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, .space8)
            } else if let browseError {
                Text(browseError).type(.body3(.regular), style: .error)
            }
        }
        .padding(Metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    private func rowLabel(_ text: String, isSelected: Bool, icon: Image) -> some View {
        HStack(spacing: .space8) {
            icon.resizable().scaledToFit()
                .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            Text(text)
                .type(.body3(.regular), style: isSelected ? .link : .primary(for: .label))
                .lineLimit(1)
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
    }

    private func loadDirectories(path: String?) async {
        isBrowsing = true
        browseError = nil
        defer { isBrowsing = false }
        do {
            let next = try await filesClient.browseAdminDirectories(store.serverURL, path)
            guard !Task.isCancelled else { return }
            listing = next
        } catch {
            guard !Task.isCancelled else { return }
            browseError = (error as? FilesClientError)?.userMessage ?? L10n.UserDetail.directoryPickerFailed
        }
    }
}

private func previewDetailState(
    userID: User.ID,
    tab: UserManagementFeature.DetailTab = .profile,
    volumesEnabled: Bool = true,
    mutate: (inout UserManagementFeature.State) -> Void = { _ in }
) -> UserManagementFeature.State {
    var state = UserManagementFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com")!,
        currentUserID: "u1"
    )
    state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
    state.detailUserID = userID
    state.detailTab = tab
    state.isUserVolumesEnabled = volumesEnabled
    if let user = state.users[id: userID] {
        state.editDisplayName = user.displayName ?? ""
        state.editUsername = user.username
        state.editEmail = user.email ?? ""
    }
    mutate(&state)
    return state
}

#Preview("Detail — profile") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u2")) {
            UserManagementFeature()
        } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Detail — security (SSO only)") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u3", tab: .security)) {
            UserManagementFeature()
        } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Detail — volumes") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u2", tab: .volumes) {
            $0.volumes = IdentifiedArray(uniqueElements: UserVolume.previewVolumes(userID: "u2"))
            $0.hasLoadedVolumesForDetail = true
        }) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Detail — admin viewing self") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u1", volumesEnabled: false)) {
            UserManagementFeature()
        } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Detail — error banner") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u2") {
            $0.detailErrorMessage = "Email already in use."
        }) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}
