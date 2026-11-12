import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// A page the Settings root pushes: a section with more than one row, or the single screen a one
/// row section stands for (Licenses).
public enum SettingsPage: Hashable, Sendable {
    case general
    case display
    case sharedFiles
    case storage
    case offline
    case administration
    case support
    case legal
    case licenses
}

extension SettingsPage {
    var title: String {
        switch self {
        case .general: SettingsMenuEntry.general.title
        case .display: SettingsMenuEntry.display.title
        case .sharedFiles: SettingsMenuEntry.sharedFiles.title
        case .storage: SettingsMenuEntry.storage.title
        case .offline: SettingsMenuEntry.offline.title
        case .administration: SettingsMenuEntry.administration.title
        case .support: SettingsMenuEntry.support.title
        case .legal: SettingsMenuEntry.legal.title
        case .licenses: L10n.Settings.rowOpenSourceLicenses
        }
    }
}

/// One row of the Settings menu, named after its section. A section with several rows opens a page
/// of them; a section with a single row does that row's job straight away.
enum SettingsMenuEntry: CaseIterable {
    case general
    case display
    case sharedFiles
    case storage
    case offline
    case administration
    case users
    case developers
    case support
    case legal
    case licenses

    var title: String {
        switch self {
        case .general: L10n.Settings.sectionGeneral
        case .display: L10n.Settings.sectionDisplay
        case .sharedFiles: L10n.Settings.uploadDefaultsRow
        case .storage: L10n.Settings.sectionStorage
        case .offline: L10n.Offline.settingsRow
        case .administration: L10n.Settings.sectionAdmin
        case .users: L10n.Settings.rowUserManagement
        case .developers: L10n.ApiTokens.navigationTitle
        case .support: L10n.Settings.sectionSupport
        case .legal: L10n.Settings.sectionLegal
        case .licenses: L10n.Settings.sectionLicenses
        }
    }

    var icon: Image {
        switch self {
        case .general: IconKit.gearshape
        case .display: IconKit.paintbrush
        case .sharedFiles: IconKit.upload
        case .storage: IconKit.storage
        case .offline: IconKit.cloud
        case .administration: IconKit.serverRack
        case .users: IconKit.people
        case .developers: IconKit.key
        case .support: IconKit.help
        case .legal: IconKit.shield
        case .licenses: IconKit.document
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        // Kept from when API Tokens was its own row, so the token UI tests still find it.
        case .developers: AccessibilityIdentifiers.Settings.apiTokensRow
        case .general: AccessibilityIdentifiers.Settings.page("general")
        case .display: AccessibilityIdentifiers.Settings.page("display")
        case .sharedFiles: AccessibilityIdentifiers.Settings.page("sharedFiles")
        case .storage: AccessibilityIdentifiers.Settings.page("storage")
        case .offline: AccessibilityIdentifiers.Settings.page("offline")
        case .administration: AccessibilityIdentifiers.Settings.page("administration")
        case .users: AccessibilityIdentifiers.Settings.page("users")
        case .support: AccessibilityIdentifiers.Settings.page("support")
        case .legal: AccessibilityIdentifiers.Settings.page("legal")
        case .licenses: AccessibilityIdentifiers.Settings.page("licenses")
        }
    }

    var isAdminOnly: Bool {
        self == .administration || self == .users
    }

    /// Support, Legal and Licenses sit in a second, untitled group under the rest.
    var isAboutTheApp: Bool {
        self == .support || self == .legal || self == .licenses
    }
}

extension EnvironmentValues {
    /// True on a Settings page that shows one section: its title is the page title, so the section
    /// leaves its own header out.
    @Entry var isSettingsSubpage = false
}

/// The header every Settings section uses; empty on a single section page.
struct SettingsSectionHeader: View {
    let title: String
    @Environment(\.isSettingsSubpage) private var isSettingsSubpage

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        if !isSettingsSubpage {
            DSFieldLabel(title)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The Settings menu: every section as one row, the app's own (Support, Legal, Licenses) in a second
/// untitled group with the footer under it. Admin only rows show for an admin.
struct SettingsMenuSection<Footer: View>: View {
    let store: StoreOf<SettingsFeature>
    let onOpen: (SettingsPage) -> Void
    @ViewBuilder var footer: Footer

    private var entries: [SettingsMenuEntry] {
        SettingsMenuEntry.allCases.filter { !$0.isAdminOnly || store.user.isAdmin }
    }

    var body: some View {
        Section {
            rows(entries.filter { !$0.isAboutTheApp })
        }
        .listRowBackground(Color.backgroundSecondary)
        Section {
            rows(entries.filter(\.isAboutTheApp))
        } footer: {
            footer
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func rows(_ entries: [SettingsMenuEntry]) -> some View {
        ForEach(entries, id: \.self) { entry in
            DSNavigationRow(title: entry.title, icon: entry.icon) {
                open(entry)
            }
            .accessibilityIdentifier(entry.accessibilityIdentifier)
        }
    }

    private func open(_ entry: SettingsMenuEntry) {
        switch entry {
        case .general: onOpen(.general)
        case .display: onOpen(.display)
        case .sharedFiles: onOpen(.sharedFiles)
        case .storage: onOpen(.storage)
        case .offline:
            if store.isOfflineOnItsOwnPage {
                onOpen(.offline)
            } else {
                store.send(.offlineDownloadButtonTapped)
            }
        case .administration: onOpen(.administration)
        case .users: store.send(.userManagementButtonTapped)
        case .developers: store.send(.apiTokensButtonTapped)
        case .support: onOpen(.support)
        case .legal: onOpen(.legal)
        case .licenses: onOpen(.licenses)
        }
    }
}

/// One section page: the grouped list, the gradient, and the page title.
struct SettingsSubpage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        DSGroupedList {
            content
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .environment(\.isSettingsSubpage, true)
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Menu, admin") {
    NavigationStack {
        DSGroupedList {
            SettingsMenuSection(store: .settingsMenuPreview(isAdmin: true), onOpen: { _ in }) { EmptyView() }
        }
        .backgroundGradient()
    }
}

#Preview("Menu, not an admin") {
    NavigationStack {
        DSGroupedList {
            SettingsMenuSection(store: .settingsMenuPreview(isAdmin: false), onOpen: { _ in }) { EmptyView() }
        }
        .backgroundGradient()
    }
}

#Preview("General page") {
    NavigationStack {
        SettingsSubpage(title: L10n.Settings.sectionGeneral) {
            GeneralSettingsSection(store: .settingsMenuPreview(isAdmin: false), filter: SettingsSearchFilter(query: ""))
        }
    }
}

private extension StoreOf<SettingsFeature> {
    static func settingsMenuPreview(isAdmin: Bool) -> StoreOf<SettingsFeature> {
        Store(initialState: SettingsFeature.State(
            serverURL: URL(string: "https://example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "1", username: "demo", email: "demo@example.com", displayName: "Demo", roles: isAdmin ? ["admin"] : [])
        )) {
            SettingsFeature()
        }
    }
}
