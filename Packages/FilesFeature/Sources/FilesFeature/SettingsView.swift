import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = .size48
    static let profileRowSpacing: CGFloat = .space12
    static let rowIconSize: CGFloat = .iconXSmall
    static let rowIconSpacing: CGFloat = .space8
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space4
    static let tagBackgroundOpacity: Double = 0.2
    static let footerTopPadding: CGFloat = .space8
    static let sheetBackdropFadeDuration: Double = 0.2
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    /// Falls back to whatever the system currently resolves to until the user has
    /// explicitly overridden it, so the toggle starts in sync with the system, exactly
    /// once, rather than carrying its own separate "system" state.
    @AppStorage("hasSetAppearanceOverride") private var hasAppearanceOverride = false
    @AppStorage("prefersDarkMode") private var prefersDarkModeOverride = false
    @Environment(\.colorScheme) private var systemColorScheme

    private var isDarkModeOn: Binding<Bool> {
        Binding(
            get: { hasAppearanceOverride ? prefersDarkModeOverride : systemColorScheme == .dark },
            set: { newValue in
                hasAppearanceOverride = true
                prefersDarkModeOverride = newValue
            }
        )
    }

    private var isConfirmingSignOut: Binding<Bool> {
        Binding(
            get: { store.isConfirmingSignOut },
            set: { isPresented in
                if !isPresented { store.send(.cancelSignOutTapped) }
            }
        )
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Constants.profileRowSpacing) {
                        AvatarView(displayName: store.displayName, size: Constants.avatarSize)

                        VStack(alignment: .leading, spacing: .space2) {
                            Text(store.displayName).type(.body2(.bold), style: .primary(for: .label))
                            if let email = store.user.email {
                                Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.tail)
                            }
                        }

                        Spacer()
                    }
                    .overlay(alignment: .topTrailing) {
                        if store.user.isAdmin {
                            roleTag
                        }
                    }

                    if let host = store.serverURL.host {
                        HStack(spacing: Constants.rowIconSpacing) {
                            IconKit.globe
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.primaryDS)
                                .frame(width: .iconSmall, height: .iconSmall)
                                .padding(.leading, .space4)
                            Text("Server").type(.body2(.regular), style: .primary(for: .label))
                                .padding(.leading, .space8)
                            Spacer()
                            Text(host).type(.body2(.regular), style: .secondary)
                        }
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(title: "Dark Mode", icon: IconKit.moonFill, isOn: isDarkModeOn)
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(
                        title: "Show Hidden Files",
                        icon: IconKit.eye,
                        isOn: $store.preferences.showHiddenFiles.sending(\.setShowHiddenFiles)
                    )
                    DSToggleRow(
                        title: "Show Thumbnails",
                        icon: IconKit.photo,
                        isOn: $store.preferences.showThumbnails.sending(\.setShowThumbnails)
                    )
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    Button(role: .destructive) {
                        store.send(.signOutButtonTapped)
                    } label: {
                        if store.isSigningOut {
                            Label {
                                Text("Signing Out\u{2026}").type(.body2(.semibold), style: .error).fontWeight(.bold)
                            } icon: {
                                ProgressView().tint(Color.primaryDS)
                            }
                        } else {
                            Label {
                                Text("Sign Out").type(.body2(.semibold), style: .error)
                            } icon: {
                                IconKit.signOut
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                            }
                        }
                    }
                    .foregroundStyle(Color.negative)
                    .disabled(store.isSigningOut)
                } footer: {
                    Text(appVersionText)
                        .type(.label4, style: .tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, Constants.footerTopPadding)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .overlay {
                // The sign-out sheet uses a custom `.height()` detent rather than `.medium`/
                // `.large`, so iOS doesn't dim/blur what's behind it the way it would for a
                // standard-sized sheet, added by hand here to match.
                if store.isConfirmingSignOut {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Constants.sheetBackdropFadeDuration), value: store.isConfirmingSignOut)
            .navigationTitle("Settings")
            .sheet(isPresented: isConfirmingSignOut) {
                SignOutConfirmationView(
                    onCancel: { store.send(.cancelSignOutTapped) },
                    onConfirm: { store.send(.confirmSignOutTapped) }
                )
            }
            .task {
                store.send(.onAppear)
            }
        }
        .tint(Color.accent)
    }

    private var roleTag: some View {
        Text("Admin".uppercased())
            .type(.caption(.semibold), style: .tertiary)
            .padding(.horizontal, Constants.tagHorizontalPadding)
            .padding(.vertical, Constants.tagVerticalPadding)
    }
}

#Preview {
    SettingsView(
        store: Store(
            initialState: SettingsFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: ["admin"])
            )
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
