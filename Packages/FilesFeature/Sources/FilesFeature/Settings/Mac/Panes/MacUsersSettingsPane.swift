#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let searchWidth: CGFloat = 320
    }

    struct MacUsersSettingsPane: View {
        @Bindable var store: StoreOf<UserManagementFeature>

        var body: some View {
            MacFormPage {
                MacTextField(
                    L10n.UserManagement.searchPrompt,
                    text: $store.searchQuery.sending(\.searchQueryChanged),
                    prompt: L10n.UserManagement.searchPrompt
                )
                .frame(width: Metrics.searchWidth)
                MacUsersTable(store: store)
                if let user = store.detailUser {
                    MacUserDetailForm(store: store, user: user)
                }
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
            .dsAlert(isPresented: Binding(get: { store.userToGrantAdmin != nil }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.shield,
                    title: L10n.UserDetail.grantAdminTitle,
                    message: store.userToGrantAdmin.map { L10n.UserDetail.grantAdminMessage($0.displayLabel) },
                    confirmTitle: L10n.UserDetail.roleGrantAdmin,
                    dismissTitle: L10n.Common.cancel,
                    role: .standard,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.grantAdminConfirmed) },
                    onDismiss: { store.send(.grantAdminCancelled) }
                )
            }
            .dsAlert(isPresented: Binding(get: { store.isConfirmingSecurityReset }, set: { _ in })) {
                securityResetAlert(store: store)
            }
            .dsAlert(isPresented: Binding(get: { store.userToDelete != nil }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.UserDetail.removeUserTitle,
                    message: store.userToDelete.map { L10n.UserDetail.removeUserMessage($0.displayLabel) },
                    confirmTitle: L10n.Common.remove,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteUserConfirmed) },
                    onDismiss: { store.send(.deleteUserCancelled) }
                )
            }
        }
    }

    #Preview("Users") {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
        state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
        state.phase = .loaded
        return MacUsersSettingsPane(store: Store(initialState: state) { UserManagementFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .previewCanvas(.settingsPane)
    }

    #Preview("Users: grant admin alert") {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
        state.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
        state.phase = .loaded
        state.userToGrantAdmin = User.previewManagedUsers.first
        return MacUsersSettingsPane(store: Store(initialState: state) { UserManagementFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .previewCanvas(.settingsPane)
    }
#endif
