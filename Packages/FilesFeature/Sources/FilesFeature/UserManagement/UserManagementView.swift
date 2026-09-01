import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The admin user list (web `UserList`). Pushed from Settings; a tap pushes `UserDetailView`
/// onto the same navigation stack.
struct UserManagementView: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @State private var isSortSheetPresented = false

    var body: some View {
        List {
            Section {
                ForEach(store.displayedUsers) { user in
                    Button {
                        store.send(.userTapped(user.id))
                    } label: {
                        UserRow(user: user)
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .top, spacing: 0) {
            PinnedTitleSearchHeader(
                title: L10n.UserManagement.navigationTitle,
                searchText: $store.searchQuery.sending(\.searchQueryChanged),
                prompt: L10n.UserManagement.searchPrompt
            )
        }
        // Title lives in the pinned header (see `PinnedTitleSearchHeader`).
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortToolbarButton(isDisabled: store.users.isEmpty) { isSortSheetPresented = true }
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.send(.createUserTapped) } label: {
                    IconKit.plus.foregroundStyle(Color.primaryDS)
                }
                .accessibilityLabel(L10n.UserManagement.createUser)
            }
        }
        .overlay { overlay }
        .refreshable { await store.send(.refreshRequested).finish() }
        .navigationDestination(isPresented: detailPresented) {
            UserDetailView(store: store)
        }
        .sheet(isPresented: createSheetPresented) {
            CreateUserSheet(store: store)
        }
        .sheet(isPresented: passwordSheetPresented) {
            SetPasswordSheet(store: store)
        }
        .sheet(isPresented: $isSortSheetPresented) {
            SortSheet(
                options: UserManagementFeature.SortOption.allCases,
                directions: BrowseFeature.SortDirection.allCases,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                optionIcon: { $0.icon },
                optionTitle: { $0.title },
                directionIcon: { $0.icon },
                directionTitle: { $0.title },
                onSelectOption: { store.send(.sortOptionChanged($0)) },
                onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                onDismiss: { isSortSheetPresented = false }
            )
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var overlay: some View {
        if store.phase == .loading && store.users.isEmpty {
            ProgressView()
        } else if let error = store.phase.errorMessage, store.users.isEmpty {
            EmptyStateView(
                icon: IconKit.warning,
                message: error
            ) {
                store.send(.refreshRequested)
            }
        } else if store.users.isEmpty {
            EmptyStateView(icon: IconKit.people, message: L10n.UserManagement.emptyList)
        } else if store.isSearchWithoutResults {
            EmptyStateView(icon: IconKit.search, message: L10n.UserManagement.noSearchMatches(store.searchQuery))
        }
    }

    // MARK: Bindings

    private var detailPresented: Binding<Bool> {
        Binding(get: { store.detailUserID != nil }, set: { if !$0 { store.send(.detailDismissed) } })
    }

    private var createSheetPresented: Binding<Bool> {
        Binding(get: { store.createSheet != nil }, set: { if !$0 { store.send(.createSheetDismissed) } })
    }

    private var passwordSheetPresented: Binding<Bool> {
        Binding(get: { store.passwordSheet != nil }, set: { if !$0 { store.send(.passwordSheetDismissed) } })
    }
}

// MARK: Shared sheet chrome

/// A label, a `DSTextField`/`DSSecureField` and an optional inline error: the repeating form
/// row shared by the user management sheets and the detail Profile tab.
struct LabeledField<Content: View>: View {
    let title: String
    var error: String?
    var isUppercased = true
    @ViewBuilder let content: Content

    init(_ title: String, error: String? = nil, uppercased: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.error = error
        self.isUppercased = uppercased
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .space4) {
            DSFieldLabel(title, uppercased: isUppercased)
            content
            if let error {
                Text(error).type(.body3(.semibold), style: .error)
            }
        }
    }
}

#Preview("List") {
    NavigationStack {
        UserManagementView(
            store: Store(
                initialState: UserManagementFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com")!,
                    currentUserID: "u1"
                )
            ) {
                UserManagementFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        UserManagementView(
            store: Store(
                initialState: UserManagementFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com")!,
                    currentUserID: "u1"
                )
            ) {
                UserManagementFeature()
            } withDependencies: {
                $0.filesClient.serverFeatures = { _ in ServerFeatures() }
                $0.filesClient.listUsers = { _ in [] }
            }
        )
    }
}

private func previewListState(
    _ mutate: (inout UserManagementFeature.State) -> Void
) -> UserManagementFeature.State {
    var state = UserManagementFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com")!,
        currentUserID: "u1"
    )
    mutate(&state)
    return state
}

#Preview("Loading") {
    NavigationStack {
        UserManagementView(store: Store(
            initialState: previewListState { $0.phase = .loading }
        ) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Load error") {
    NavigationStack {
        UserManagementView(store: Store(
            initialState: previewListState { $0.phase = .failed("Couldn't reach the server.") }
        ) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Search — no results") {
    NavigationStack {
        UserManagementView(store: Store(
            initialState: previewListState {
                $0.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
                $0.searchQuery = "nobody"
            }
        ) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}
