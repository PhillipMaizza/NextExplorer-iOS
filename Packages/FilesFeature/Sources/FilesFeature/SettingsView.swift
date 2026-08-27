import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = .size48
    static let profileRowSpacing: CGFloat = .space12
    static let rowIconSize: CGFloat = .iconSmall
    static let rowIconSpacing: CGFloat = .space8
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space4
    static let tagBorderWidth: CGFloat = 1
    static let footerTopPadding: CGFloat = .space8
    static let signOutFadeDuration: Double = 0.15
    static let fullOpacity: Double = 1.0
    static let disabledOpacity: Double = 0.5
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    /// Falls back to whatever the system currently resolves to until the user has
    /// explicitly overridden it, so the toggle starts in sync with the system, exactly
    /// once, rather than carrying its own separate "system" state.
    @AppStorage("hasSetAppearanceOverride") private var hasAppearanceOverride = false
    @AppStorage("prefersDarkMode") private var prefersDarkModeOverride = false
    @AppStorage("dateDisplayFormat") private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage("renderHTMLPages") private var renderHTMLPages = false
    @AppStorage("renderMarkdownPages") private var renderMarkdownPages = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("showFilenameExtensions") private var showFilenameExtensions = true
    @AppStorage("removeArchiveAfterDownload") private var removeArchiveAfterDownload = false
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

    private var dateFormat: Binding<DateDisplayFormat> {
        Binding(
            get: { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system },
            set: { dateFormatRaw = $0.rawValue }
        )
    }

    private var thumbnailSize: Binding<ThumbnailSize> {
        Binding(
            get: { ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium },
            set: { thumbnailSizeRaw = $0.rawValue }
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

    private var isConfirmingRemoveAllDownloads: Binding<Bool> {
        Binding(
            get: { store.removeAllDownloadsConfirmationIsPresented },
            set: { isPresented in
                if !isPresented { store.send(.removeAllDownloadsCancelled) }
            }
        )
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var isConfirmingClearCache: Binding<Bool> {
        Binding(
            get: { store.clearCacheConfirmationIsPresented },
            set: { isPresented in
                if !isPresented { store.send(.clearCacheCancelled) }
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
                    .listRowSeparator(.hidden, edges: .bottom)

                    if let host = store.serverURL.host {
                        HStack(spacing: Constants.rowIconSpacing) {
                            IconKit.server
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: .iconSmall, height: .iconSmall)
                                .padding(.leading, .space4)
                            Text("Server").type(.body2(.regular), style: .primary(for: .label))
                                .padding(.leading, .space8)
                            Spacer()
                            Text(host).type(.body2(.regular), style: .secondary)
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }

                    signOutRow
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(title: "Dark Mode", icon: IconKit.darkMode, isOn: isDarkModeOn)
                    DSToggleRow(
                        title: "Show Thumbnails",
                        icon: IconKit.photo,
                        isOn: $store.preferences.showThumbnails.sending(\.setShowThumbnails)
                    )
                    Picker(selection: thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    } label: {
                        Label {
                            Text("Thumbnail Size").type(.body2(.regular), style: .primary(for: .label))
                        } icon: {
                            IconKit.squareGrid
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.secondaryDS)
                    .hapticFeedback(.selection, trigger: thumbnailSizeRaw)
                    DSToggleRow(
                        title: "Show Filename Extensions",
                        icon: IconKit.tag,
                        isOn: $showFilenameExtensions
                    )
                } header: {
                    sectionHeader("Display")
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(
                        title: "Show Hidden Files",
                        icon: IconKit.eye,
                        isOn: $store.preferences.showHiddenFiles.sending(\.setShowHiddenFiles)
                    )
                    DSToggleRow(
                        title: "Render HTML Pages",
                        icon: IconKit.web,
                        isOn: $renderHTMLPages
                    )
                    DSToggleRow(
                        title: "Render Markdown Files",
                        icon: IconKit.textformat,
                        isOn: $renderMarkdownPages
                    )
                    NavigationLink {
                        DateFormatPickerView(selection: dateFormat)
                    } label: {
                        Label {
                            HStack {
                                Text("Date Format").type(.body2(.regular), style: .primary(for: .label))
                                Spacer()
                                Text(dateFormat.wrappedValue.title).type(.body2(.regular), style: .secondary)
                            }
                        } icon: {
                            IconKit.calendar
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                    DSToggleRow(
                        title: "Haptics",
                        icon: IconKit.haptics,
                        isOn: $hapticsEnabled
                    )
                } header: {
                    sectionHeader("General")
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(
                        title: "Remove Archives After Download",
                        icon: IconKit.archivePage,
                        isOn: $removeArchiveAfterDownload
                    )
                    Button(role: .destructive) {
                        store.send(.removeAllDownloadsTapped)
                    } label: {
                        Label {
                            HStack {
                                Text("Remove All Downloads").type(.body2(.regular), style: .link)
                                Spacer()
                                Text(Self.byteFormatter.string(fromByteCount: store.downloadsSize)).type(.body2(.regular), style: .secondary)
                            }
                        } icon: {
                            IconKit.delete
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .disabled(store.isRemovingAllDownloads || !store.hasDownloads)
                    Button(role: .destructive) {
                        store.send(.clearCacheTapped)
                    } label: {
                        Label {
                            HStack {
                                Text("Clear Cache").type(.body2(.regular), style: .link)
                                Spacer()
                                Text(Self.byteFormatter.string(fromByteCount: store.cacheSize)).type(.body2(.regular), style: .secondary)
                            }
                        } icon: {
                            IconKit.delete
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .disabled(store.isClearingCache || store.cacheSize == 0)
                } header: {
                    sectionHeader("Storage")
                } footer: {
                    Text("Downloading a folder zips it on the server first. Turn on the toggle above to delete that archive from the server once it's saved to your device. Removing downloads or clearing the cache only affects this device; nothing on the server is touched.")
                        .type(.body3(.regular), style: .tertiary)
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label {
                            Text("Open Source Licenses").type(.body2(.regular), style: .primary(for: .label))
                        } icon: {
                            IconKit.document
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                } header: {
                    sectionHeader("Licenses")
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
            .navigationTitle("Settings")
            // `.alert`, not `.confirmationDialog`: a confirmationDialog presents as a
            // popover anchored to some ambient source view on the `.pad` idiom (this app
            // also targets iPad) rather than a full-width bottom sheet. `.alert` is always
            // a centered modal regardless of idiom, so there's no anchor to get wrong.
            .alert("Sign Out?", isPresented: isConfirmingSignOut) {
                Button("Log Out", role: .destructive) { store.send(.confirmSignOutTapped) }
                Button("Cancel", role: .cancel) { store.send(.cancelSignOutTapped) }
            } message: {
                Text("You'll need to sign in again to access your files.")
            }
            .alert("Remove All Downloads?", isPresented: isConfirmingRemoveAllDownloads) {
                Button("Remove All", role: .destructive) { store.send(.removeAllDownloadsConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.removeAllDownloadsCancelled) }
            } message: {
                Text("This deletes every downloaded file from this device. They stay on the server.")
            }
            .hapticFeedback(.warning, trigger: store.removeAllDownloadsConfirmationIsPresented)
            .alert("Clear Cache?", isPresented: isConfirmingClearCache) {
                Button("Clear", role: .destructive) { store.send(.clearCacheConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.clearCacheCancelled) }
            } message: {
                Text("This clears cached previews and thumbnails. Nothing on the server is affected.")
            }
            .hapticFeedback(.warning, trigger: store.clearCacheConfirmationIsPresented)
            .task {
                store.send(.onAppear)
            }
        }
        .tint(Color.accent)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).type(.body3(.semibold), style: .secondary).textCase(.uppercase)
    }

    /// Plain, centered, icon-less.
    private var signOutRow: some View {
        Button(role: .destructive) {
            store.send(.signOutButtonTapped)
        } label: {
            HStack(spacing: Constants.rowIconSpacing) {
                if store.isSigningOut {
                    ProgressView().tint(Color.negative)
                }
                Text(store.isSigningOut ? "Signing Out\u{2026}" : "Sign Out")
                    .type(.body2(.semibold), style: .error)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(store.isSigningOut)
        .animation(.easeInOut(duration: Constants.signOutFadeDuration), value: store.isSigningOut)
        .buttonStyle(DSHapticButtonStyle())
    }

    private var roleTag: some View {
        Text("Admin".uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Constants.tagHorizontalPadding)
            .padding(.vertical, Constants.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall, ).strokeBorder(Color.accent, lineWidth: Constants.tagBorderWidth)
            )
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
