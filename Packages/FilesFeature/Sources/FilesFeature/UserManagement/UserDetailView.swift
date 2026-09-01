import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private typealias Metrics = UserDetailMetrics

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
                        DSErrorCard(error)
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
                        ProfileTabView(store: store, user: user)
                    case .security:
                        SecurityTabView(store: store, user: user)
                    case .volumes:
                        VolumesTabView(store: store)
                    }
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.contentSpacing)
            }
        }
        .backgroundGradient()
        .navigationTitle(store.detailUser?.displayName ?? store.detailUser?.username ?? L10n.UserDetail.fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: volumeSheetPresented) {
            VolumeAssignSheet(store: store)
        }
        .sheet(isPresented: removeVolumeAlertPresented) {
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
        .sheet(isPresented: deleteAlertPresented) {
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

    // MARK: Sheet bindings

    private var volumeSheetPresented: Binding<Bool> {
        Binding(get: { store.volumeSheet != nil }, set: { if !$0 { store.send(.volumeSheetDismissed) } })
    }

    // No op setters: both confirmation sheets are dismiss disabled and only close through one
    // of `DSAlertSheet`'s own buttons, which drive the reducer directly.
    private var removeVolumeAlertPresented: Binding<Bool> {
        Binding(get: { store.volumeToRemove != nil }, set: { _ in })
    }

    /// Lives here, not on the list view: the "Remove User" button is in this screen's Danger
    /// Zone, so the confirmation must present over the detail page. Attached to the list it
    /// surfaced one navigation level below, behind the pushed detail.
    private var deleteAlertPresented: Binding<Bool> {
        Binding(get: { store.userToDelete != nil }, set: { _ in })
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
            $0.volumesPhase = .loaded
        }) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Detail — volumes loading") {
    NavigationStack {
        UserDetailView(store: Store(initialState: previewDetailState(userID: "u2", tab: .volumes) {
            $0.volumesPhase = .loading
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
