import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let avatarSize: CGFloat = .size40
    static let rowSpacing: CGFloat = .space12
    static let authIconSize: CGFloat = .iconXSmall
    static let authIconChipSize: CGFloat = .size24
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space2
    static let tagBorderWidth: CGFloat = 1
    static let sheetContentSpacing: CGFloat = .space24
    static let sheetHorizontalPadding: CGFloat = .space24
    static let sheetMaxHeightFraction: CGFloat = 0.9
}

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
        .navigationTitle(L10n.UserManagement.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.UserManagement.searchPrompt
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortToolbarButton(isDisabled: store.users.isEmpty) { isSortSheetPresented = true }
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.send(.createUserTapped) } label: {
                    IconKit.plus.fontWeight(.bold).foregroundStyle(Color.accent)
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
        if store.isLoading && store.users.isEmpty {
            ProgressView()
        } else if let error = store.errorMessage, store.users.isEmpty {
            EmptyStateView(icon: IconKit.warning, message: error) {
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

// MARK: Row

private struct UserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)

            VStack(alignment: .leading, spacing: .space2) {
                HStack(spacing: .space8) {
                    Text(user.displayName ?? user.username)
                        .type(.body2(.semibold), style: .primary(for: .label))
                        .lineLimit(1)
                    if user.isAdmin {
                        AdminTag()
                    }
                }
                if let email = user.email {
                    Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: .space8)

            AuthMethodChips(methods: user.authMethods)

            IconKit.chevronRight
                .resizable().scaledToFit()
                .foregroundStyle(Color.tertiaryDS)
                .frame(width: Metrics.authIconSize, height: Metrics.authIconSize)
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
    }
}

/// The accent outlined "ADMIN" pill, matching the one on the Settings profile card.
struct AdminTag: View {
    var body: some View {
        Text(L10n.UserManagement.badgeAdmin.uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Metrics.tagHorizontalPadding)
            .padding(.vertical, Metrics.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .strokeBorder(Color.accent, lineWidth: Metrics.tagBorderWidth)
            )
    }
}

/// Overlapping circular chips, one per sign in method: key for a local password, cloud for
/// SSO. Mirrors the web list's login type cluster.
struct AuthMethodChips: View {
    let methods: [AuthMethod]

    var body: some View {
        HStack(spacing: -Metrics.authIconSize / 2) {
            ForEach(Array(methods.enumerated()), id: \.offset) { _, method in
                (method.isPassword ? IconKit.key : IconKit.cloud)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.authIconSize, height: Metrics.authIconSize)
                    .frame(width: Metrics.authIconChipSize, height: Metrics.authIconChipSize)
                    .background(Circle().fill(Color.backgroundPrimary))
                    .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: 2))
            }
        }
    }
}

// MARK: Create User sheet

private struct CreateUserSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.sheetMaxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                DSSheetHeader(
                    icon: IconKit.people,
                    title: L10n.UserManagement.createNavigationTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                if let sheet = store.createSheet {
                    if let error = sheet.errorMessage {
                        DSErrorCard(error)
                    }
                    LabeledField(L10n.UserManagement.createEmailField, error: sheet.emailError, uppercased: false) {
                        DSTextField(L10n.UserManagement.createEmailPlaceholder, text: fieldBinding(\.email, UserManagementFeature.Action.createEmailChanged))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledField(L10n.UserManagement.createUsernameField, uppercased: false) {
                        DSTextField(L10n.UserManagement.createUsernamePlaceholder, text: fieldBinding(\.username, UserManagementFeature.Action.createUsernameChanged))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledField(L10n.Common.password, error: sheet.passwordError, uppercased: false) {
                        DSSecureField(L10n.UserManagement.createPasswordPlaceholder(CredentialRules.minimumPasswordLength), text: fieldBinding(\.password, UserManagementFeature.Action.createPasswordChanged))
                    }
                    DSToggleRow(
                        title: L10n.UserManagement.createGrantAdminToggle,
                        subtitle: L10n.UserManagement.createGrantAdminSubtitle,
                        icon: IconKit.shield,
                        isOn: Binding(
                            get: { store.createSheet?.isAdmin ?? false },
                            set: { store.send(.createIsAdminChanged($0)) }
                        )
                    )
                }
            }
            .padding(.horizontal, Metrics.sheetHorizontalPadding)
            .padding(.vertical, Metrics.sheetContentSpacing)
        } footer: {
            DSSheetFooter {
                DSButton(L10n.UserManagement.createSubmit, style: .primary, isLoading: store.createSheet?.isSubmitting ?? false) {
                    store.send(.createSubmitTapped)
                }
                .disabled(!(store.createSheet?.isSubmitEnabled ?? false))
            }
        }
    }

    private func fieldBinding(
        _ keyPath: KeyPath<UserManagementFeature.CreateUserState, String>,
        _ action: @escaping (String) -> UserManagementFeature.Action
    ) -> Binding<String> {
        Binding(
            get: { store.createSheet?[keyPath: keyPath] ?? "" },
            set: { store.send(action($0)) }
        )
    }
}

// MARK: Set password sheet

private struct SetPasswordSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.sheetMaxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                DSSheetHeader(
                    icon: IconKit.key,
                    title: L10n.UserManagement.setPasswordNavigationTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                if let sheet = store.passwordSheet {
                    if let error = sheet.errorMessage {
                        DSErrorCard(error)
                    }
                    Text(sheet.hasExistingPassword
                        ? L10n.UserManagement.setPasswordResetIntro(sheet.userLabel)
                        : L10n.UserManagement.setPasswordSetIntro(sheet.userLabel))
                        .type(.body3(.regular), style: .secondary)

                    LabeledField(L10n.UserManagement.setPasswordNewField, error: sheet.passwordError, uppercased: false) {
                        DSSecureField(L10n.UserManagement.setPasswordPlaceholder(CredentialRules.minimumPasswordLength), text: Binding(
                            get: { store.passwordSheet?.password ?? "" },
                            set: { store.send(.passwordFieldChanged($0)) }
                        ))
                    }
                }
            }
            .padding(.horizontal, Metrics.sheetHorizontalPadding)
            .padding(.vertical, Metrics.sheetContentSpacing)
        } footer: {
            DSSheetFooter {
                DSButton(
                    (store.passwordSheet?.hasExistingPassword ?? false) ? L10n.UserManagement.setPasswordResetTitle : L10n.UserManagement.setPasswordSetTitle,
                    style: .primary,
                    isLoading: store.passwordSheet?.isSubmitting ?? false
                ) {
                    store.send(.passwordSubmitTapped)
                }
                .disabled(!(store.passwordSheet?.isSubmitEnabled ?? false))
            }
        }
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
            initialState: previewListState { $0.isLoading = true }
        ) { UserManagementFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
}

#Preview("Load error") {
    NavigationStack {
        UserManagementView(store: Store(
            initialState: previewListState { $0.errorMessage = "Couldn't reach the server." }
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
