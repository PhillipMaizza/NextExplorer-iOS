#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listWidth: CGFloat = 210
        static let avatarSize: CGFloat = .size32
        static let rowSpacing: CGFloat = .space8
        static let barPadding: CGFloat = .space8
    }

    /// The Users pane: every user on the server down the left, searchable and sortable, with
    /// the selected one's profile and sign in options on the right.
    struct MacUsersSettingsPane: View {
        @Bindable var store: StoreOf<UserManagementFeature>

        private var selection: Binding<User.ID?> {
            Binding(get: { store.detailUserID }, set: { id in
                if let id, id != store.detailUserID {
                    store.send(.userTapped(id))
                }
            })
        }

        var body: some View {
            HStack(spacing: 0) {
                userList
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task { store.send(.onAppear) }
            .onChange(of: store.displayedUsers.first?.id, initial: true) { _, firstID in
                if store.detailUserID == nil, let firstID {
                    store.send(.userTapped(firstID))
                }
            }
            .sheet(isPresented: Binding(get: { store.createSheet != nil }, set: {
                if !$0 {
                    store.send(.createSheetDismissed)
                }
            })) {
                MacCreateUserSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.passwordSheet != nil }, set: {
                if !$0 {
                    store.send(.passwordSheetDismissed)
                }
            })) {
                MacSetPasswordSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.volumeSheet != nil }, set: {
                if !$0 {
                    store.send(.volumeSheetDismissed)
                }
            })) {
                MacVolumeAssignSheet(store: store)
            }
            .dsAlert(isPresented: Binding(get: { store.volumeToRemove != nil }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.drive,
                    title: L10n.UserDetail.removeVolumeTitle,
                    message: store.volumeToRemove.map { L10n.UserDetail.removeVolumeMessage($0.label) },
                    confirmTitle: L10n.Common.remove,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.removeVolumeConfirmed) },
                    onDismiss: { store.send(.removeVolumeCancelled) }
                )
            }
            .dsAlert(isPresented: Binding(get: { store.userToDelete != nil }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.UserDetail.removeUserTitle,
                    message: store.userToDelete.map { L10n.UserDetail.removeUserMessage($0.displayName ?? $0.username) },
                    confirmTitle: L10n.Common.remove,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteUserConfirmed) },
                    onDismiss: { store.send(.deleteUserCancelled) }
                )
            }
        }

        private var userList: some View {
            VStack(spacing: 0) {
                TextField(L10n.UserManagement.searchPrompt, text: $store.searchQuery.sending(\.searchQueryChanged))
                    .textFieldStyle(.roundedBorder)
                    .padding(Metrics.barPadding)
                List(store.displayedUsers, selection: selection) { user in
                    MacUserRow(user: user).tag(user.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .overlay { listOverlay }
                Divider()
                HStack {
                    MacTableBarButton(icon: IconKit.plus, label: L10n.UserManagement.createUser) {
                        store.send(.createUserTapped)
                    }
                    Spacer()
                    MacSortMenu(
                        options: UserManagementFeature.SortOption.allCases,
                        directions: BrowseFeature.SortDirection.allCases,
                        sortOption: store.sortOption,
                        sortDirection: store.sortDirection,
                        optionTitle: { $0.title },
                        directionTitle: { $0.title },
                        onSelectOption: { store.send(.sortOptionChanged($0)) },
                        onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                        isDisabled: store.users.isEmpty
                    )
                    .fixedSize()
                }
                .padding(Metrics.barPadding)
            }
            .frame(width: Metrics.listWidth)
        }

        @ViewBuilder
        private var listOverlay: some View {
            if store.phase == .loading, store.users.isEmpty {
                MacSpinner()
            } else if let error = store.phase.errorMessage, store.users.isEmpty {
                VStack(spacing: .space8) {
                    Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L10n.Common.retry) { store.send(.refreshRequested) }
                }
                .padding()
            } else if store.isSearchWithoutResults {
                Text(L10n.UserManagement.noSearchMatches(store.searchQuery))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }

        @ViewBuilder
        private var detail: some View {
            if let user = store.detailUser {
                MacUserDetailForm(store: store, user: user)
            } else if store.users.isEmpty, store.phase != .loading {
                // Only when there is truly nobody: a transparent copy would still be read aloud.
                Text(L10n.UserManagement.emptyList)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct MacUserRow: View {
        let user: User

        var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)
                VStack(alignment: .leading) {
                    Text(user.displayName ?? user.username).lineLimit(1)
                    if let email = user.email {
                        Text(email)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if user.isAdmin {
                    Text(L10n.UserManagement.badgeAdmin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("Users") {
        var state = UserManagementFeature.State(serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"), currentUserID: "u1")
        state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
        state.phase = .loaded
        return MacUsersSettingsPane(store: Store(initialState: state) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
            .previewCanvas(.settingsPane)
    }
#endif
