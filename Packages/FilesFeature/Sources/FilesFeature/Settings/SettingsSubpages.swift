import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// A Settings section with more than two rows lives on its own page, reached from a row named
/// after it, so the root stays short. Each page shows the same section view the root used to.
public enum SettingsPage: Hashable, CaseIterable, Sendable {
    case general
    case display
    case storage
    case offline
    case administration

    var title: String {
        switch self {
        case .general: L10n.Settings.sectionGeneral
        case .display: L10n.Settings.sectionDisplay
        case .storage: L10n.Settings.sectionStorage
        case .offline: L10n.Offline.sectionTitle
        case .administration: L10n.Settings.sectionAdmin
        }
    }

    var icon: Image {
        switch self {
        case .general: IconKit.gearshape
        case .display: IconKit.paintbrush
        case .storage: IconKit.storage
        case .offline: IconKit.cloud
        case .administration: IconKit.serverRack
        }
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

/// The root's rows into the section pages. Administration only shows for an admin.
struct SettingsMenuSection: View {
    let store: StoreOf<SettingsFeature>
    let onOpen: (SettingsPage) -> Void

    private var pages: [SettingsPage] {
        SettingsPage.allCases.filter { $0 != .administration || store.user.isAdmin }
    }

    var body: some View {
        Section {
            ForEach(pages, id: \.self) { page in
                DSNavigationRow(title: page.title, icon: page.icon) {
                    onOpen(page)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.page(page.accessibilityName))
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}

private extension SettingsPage {
    var accessibilityName: String {
        switch self {
        case .general: "general"
        case .display: "display"
        case .storage: "storage"
        case .offline: "offline"
        case .administration: "administration"
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
            SettingsMenuSection(store: .settingsMenuPreview(isAdmin: true), onOpen: { _ in })
        }
        .backgroundGradient()
    }
}

#Preview("Menu, not an admin") {
    NavigationStack {
        DSGroupedList {
            SettingsMenuSection(store: .settingsMenuPreview(isAdmin: false), onOpen: { _ in })
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
