import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum Metrics {
    static let avatarSize: CGFloat = .size40
    static let rowSpacing: CGFloat = .space12
    static let authIconSize: CGFloat = .iconXSmall
    static let authIconChipSize: CGFloat = .size24
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space2
    static let tagBorderWidth: CGFloat = 1
    static let sheetContentSpacing: CGFloat = .space16
    static let sheetHorizontalPadding: CGFloat = .space16
    static let fieldHeight: CGFloat = .size48
    static let fieldHorizontalPadding: CGFloat = .space12
    static let cardCornerRadius: CGFloat = .radiusMedium
    static let cardPadding: CGFloat = .space12
    static let closeIconSize: CGFloat = .iconXSmall
}

/// The trailing `xmark` every management sheet dismisses with — replaces a bare "Cancel"
/// text button so the sheets read as dismissable panels, not commit/cancel forms.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconKit.close
                .resizable().scaledToFit()
                .foregroundStyle(Color.primaryDS)
                .frame(width: Metrics.closeIconSize, height: Metrics.closeIconSize)
        }
        .buttonStyle(DSHapticButtonStyle())
        .accessibilityLabel("Close")
    }
}

/// The admin user list (web `UserList`). Pushed from Settings; taps push `UserDetailView`
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
        .background(Color.backgroundPrimary)
        .navigationTitle("User Management")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search users"
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isSortSheetPresented = true } label: {
                    Label { Text("Sort") } icon: { IconKit.sort.foregroundStyle(Color.accent) }
                }
                .tint(.accent)
                .buttonStyle(DSHapticButtonStyle())
                .disabled(store.users.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { store.send(.createUserTapped) } label: {
                    Label { Text("Create User") } icon: { IconKit.plus.foregroundStyle(Color.accent) }
                }
                .tint(.accent)
                .buttonStyle(DSHapticButtonStyle())
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
            EmptyStateView(icon: IconKit.people, message: "No users yet.")
        } else if store.isSearchWithoutResults {
            EmptyStateView(icon: IconKit.search, message: "No users match \u{201C}\(store.searchQuery)\u{201D}.")
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

// MARK: - Row

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

/// The accent-outlined "ADMIN" pill, matching the one on the Settings profile card.
struct AdminTag: View {
    var body: some View {
        Text("Admin".uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Metrics.tagHorizontalPadding)
            .padding(.vertical, Metrics.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .strokeBorder(Color.accent, lineWidth: Metrics.tagBorderWidth)
            )
    }
}

/// Overlapping circular chips, one per sign-in method — key for a local password, cloud for
/// SSO. Mirrors the web list's login-type cluster.
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

// MARK: - Create User sheet

private struct CreateUserSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                    if let sheet = store.createSheet {
                        if let error = sheet.errorMessage {
                            ErrorBanner(text: error)
                        }
                        LabeledField("Email", error: sheet.emailError) {
                            TextField("name@example.com", text: fieldBinding(\.email, UserManagementFeature.Action.createEmailChanged))
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledField("Username (optional)") {
                            TextField("Derived from email", text: fieldBinding(\.username, UserManagementFeature.Action.createUsernameChanged))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledField("Password", error: sheet.passwordError) {
                            SecureField("At least 6 characters", text: fieldBinding(\.password, UserManagementFeature.Action.createPasswordChanged))
                        }
                        DSToggleRow(
                            title: "Grant admin access",
                            subtitle: "Full control over files, shares and users.",
                            icon: IconKit.shield,
                            isOn: Binding(
                                get: { store.createSheet?.isAdmin ?? false },
                                set: { store.send(.createIsAdminChanged($0)) }
                            )
                        )
                        DSButton("Create User", style: .primary, isLoading: sheet.isSubmitting) {
                            store.send(.createSubmitTapped)
                        }
                        .disabled(!sheet.isSubmitEnabled)
                        .padding(.top, .space4)
                    }
                }
                .padding(.horizontal, Metrics.sheetHorizontalPadding)
                .padding(.vertical, Metrics.sheetContentSpacing)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Create User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

// MARK: - Set password sheet

private struct SetPasswordSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sheetContentSpacing) {
                    if let sheet = store.passwordSheet {
                        if let error = sheet.errorMessage {
                            ErrorBanner(text: error)
                        }
                        Text(sheet.hasExistingPassword
                            ? "Set a new local password for \(sheet.userLabel). Their current password stops working."
                            : "Give \(sheet.userLabel) a local password so they can sign in without SSO.")
                            .type(.body3(.regular), style: .secondary)

                        LabeledField("New password", error: sheet.passwordError) {
                            SecureField("At least 6 characters", text: Binding(
                                get: { store.passwordSheet?.password ?? "" },
                                set: { store.send(.passwordFieldChanged($0)) }
                            ))
                        }

                        DSButton(
                            sheet.hasExistingPassword ? "Reset Password" : "Set Password",
                            style: .primary,
                            isLoading: sheet.isSubmitting
                        ) {
                            store.send(.passwordSubmitTapped)
                        }
                        .disabled(!sheet.isSubmitEnabled)
                        .padding(.top, .space4)
                    }
                }
                .padding(.horizontal, Metrics.sheetHorizontalPadding)
                .padding(.vertical, Metrics.sheetContentSpacing)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Shared sheet chrome

/// Label + `FieldBox` + optional inline error — the repeating form row shared by the
/// user-management sheets and the detail Profile tab.
struct LabeledField<Content: View>: View {
    let title: String
    var error: String?
    @ViewBuilder let content: Content

    init(_ title: String, error: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.error = error
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .space4) {
            Text(title).type(.body3(.semibold), style: .secondary)
            FieldBox { content }
            if let error {
                Text(error).type(.caption(.regular), style: .error)
            }
        }
    }
}

/// Rounded outlined container for a single-line text field inside a sheet form.
struct FieldBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .type(.body2(.regular))
            .foregroundStyle(Color.primaryDS)
            .frame(height: Metrics.fieldHeight)
            .padding(.horizontal, Metrics.fieldHorizontalPadding)
            .background(RoundedRectangle(cornerRadius: .radiusControl).fill(Color.backgroundSecondary))
            .overlay(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline)
            )
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .type(.body3(.regular), style: .error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.cardPadding)
            .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.negative.opacity(0.12)))
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
