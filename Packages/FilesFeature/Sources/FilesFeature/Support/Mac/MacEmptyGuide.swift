#if os(macOS)
    import AppStorageKeys
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let bulletIconSize: CGFloat = .size16
        static let highlightTint: Double = .opacitySelection
        static let menuWidth: CGFloat = 220
    }

    @MainActor
    final class MacSectionOpener {
        private let open: () -> Void

        init(_ open: @escaping () -> Void) {
            self.open = open
        }

        func callAsFunction() {
            open()
        }
    }

    extension EnvironmentValues {
        @Entry var showMacBrowse: MacSectionOpener?
        @Entry var showMacSharedWithMe: MacSectionOpener?
        @Entry var showMacEnclosingFolder: MacSectionOpener?
        @Entry var showMacPreviousFolder: MacSectionOpener?
        @Entry var retryMacFolder: MacSectionOpener?
        @Entry var canOpenMacAccessRules = false
    }

    struct MacEmptyGuideKey: PreferenceKey {
        static let defaultValue: ListGuide? = nil

        static func reduce(value: inout ListGuide?, nextValue: () -> ListGuide?) {
            value = value ?? nextValue()
        }
    }

    extension View {
        func macEmptyGuide(_ guide: ListGuide?) -> some View {
            preference(key: MacEmptyGuideKey.self, value: guide)
        }

        func macFailureGuide(_ guide: ListGuide?) -> some View {
            transformPreference(MacEmptyGuideKey.self) { value in
                value = guide ?? value
            }
        }

        func macEmptyGuideOverlay() -> some View {
            overlayPreferenceValue(MacEmptyGuideKey.self) { guide in
                ZStack {
                    if let guide {
                        MacListGuideView(guide: guide)
                            .transition(.opacity)
                    }
                }
                .animation(DSMotion.stateFade, value: guide)
            }
        }
    }

    struct MacEmptyGuideMessage: View {
        enum Destination {
            case browse, sharedWithMe

            var title: String {
                switch self {
                case .browse: L10n.EmptyGuide.goToBrowse
                case .sharedWithMe: L10n.EmptyGuide.goToShared
                }
            }
        }

        let message: String
        var destination: Destination? = .browse
        @Environment(\.showMacBrowse) private var showBrowse
        @Environment(\.showMacSharedWithMe) private var showSharedWithMe

        var body: some View {
            Text(message)
                .type(.body1(.regular), style: .secondary)
            if let destination, let open = opener(for: destination) {
                Button(destination.title) { open() }
                    .buttonStyle(.macDS(.primary))
                    .padding(.top, .space4)
            }
        }

        private func opener(for destination: Destination) -> MacSectionOpener? {
            switch destination {
            case .browse: showBrowse
            case .sharedWithMe: showSharedWithMe
            }
        }
    }

    struct MacEmptyGuideMenu: View {
        enum Item: CaseIterable {
            case open, favorite, share, offline, delete

            var title: String {
                switch self {
                case .open: L10n.Browse.open
                case .share: L10n.Browse.actionShare
                case .offline: L10n.Browse.actionAvailableOffline
                case .favorite: L10n.Browse.actionAddToFavorites
                case .delete: L10n.Browse.actionDelete
                }
            }

            var icon: Image {
                switch self {
                case .open: IconKit.macOpen
                case .share: IconKit.macSidebarShared
                case .offline: IconKit.macDownload
                case .favorite: IconKit.macStar
                case .delete: IconKit.macTrash
                }
            }
        }

        let highlighted: Item

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                ForEach(Item.allCases, id: \.self) { item in
                    if item == .favorite || item == .delete {
                        MacActionMenuDivider()
                    }
                    MacActionMenuRow(item.title, icon: item.icon, isDestructive: item == .delete)
                        .background(
                            item == highlighted ? Color.accent.opacity(Metrics.highlightTint) : Color.clear,
                            in: RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        )
                }
            }
            .padding(.space4)
            .frame(width: Metrics.menuWidth)
            .background(Color.macCard, in: RoundedRectangle(cornerRadius: .radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .strokeBorder(Color.macLine, lineWidth: .borderWidthHairline)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    struct MacMenuEmptyGuide: View {
        let title: String
        let message: String
        let highlighted: MacEmptyGuideMenu.Item

        var body: some View {
            EmptyGuide(title: title) {
                MacEmptyGuideMenu(highlighted: highlighted)
            } detail: {
                MacEmptyGuideMessage(message: message)
            }
        }
    }

    struct MacReadOnlyFolderGuide: View {
        let canDownload: Bool
        @Environment(\.showMacEnclosingFolder) private var enclosingFolder
        @Environment(\.canOpenMacAccessRules) private var canOpenAccessRules
        @Environment(\.openSettings) private var openSettings
        @AppStorage(AppStorageKeys.macSettingsPane) private var settingsPane = MacSettingsCategory.appearance

        var body: some View {
            EmptyGuide(title: L10n.EmptyGuide.readOnlyTitle) {
                EmptyGuideTile(icon: IconKit.macLock)
            } detail: {
                EmptyGuideBullet(
                    icon: IconKit.macEye,
                    text: canDownload ? L10n.EmptyGuide.readOnlyOpen : L10n.EmptyGuide.readOnlyOpenOnly
                )
                EmptyGuideBullet(icon: IconKit.macLock, text: L10n.EmptyGuide.readOnlyLocked)
                HStack(spacing: .space8) {
                    if let enclosingFolder {
                        Button { enclosingFolder() } label: {
                            Label {
                                Text(L10n.Menu.enclosingFolder)
                            } icon: {
                                IconKit.macToolbarUp
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: Metrics.bulletIconSize, height: Metrics.bulletIconSize)
                            }
                        }
                        .buttonStyle(.macDS(.primary))
                    }
                    if canOpenAccessRules {
                        Button(L10n.EmptyGuide.openAccessRules(L10n.AccessRules.navigationTitle)) {
                            settingsPane = .accessRules
                            openSettings()
                        }
                        .buttonStyle(.macDS(.secondary))
                    }
                }
                .padding(.top, .space8)
            }
        }
    }

    struct MacListGuideView: View {
        let guide: ListGuide

        var body: some View {
            switch guide {
            case .favorites:
                MacMenuEmptyGuide(
                    title: L10n.EmptyGuide.favoritesTitle,
                    message: L10n.EmptyGuide.favoritesBody(L10n.Browse.actionAddToFavorites, L10n.Favorites.actionEdit),
                    highlighted: .favorite
                )
            case .sharedByMe:
                MacMenuEmptyGuide(
                    title: L10n.EmptyGuide.sharedTitle,
                    message: L10n.EmptyGuide.sharedBody(L10n.Browse.actionShare),
                    highlighted: .share
                )
            case .sharedWithMe:
                EmptyGuide(title: L10n.EmptyGuide.sharedWithMeTitle) {
                    EmptyGuideTile(icon: IconKit.macSidebarShared)
                } detail: {
                    MacEmptyGuideMessage(message: L10n.Shared.emptyWithMe, destination: nil)
                }
            case .offline:
                MacMenuEmptyGuide(
                    title: L10n.EmptyGuide.offlineTitle,
                    message: L10n.EmptyGuide.offlineBody(L10n.Browse.actionAvailableOffline),
                    highlighted: .offline
                )
            case let .trash(retentionDays):
                EmptyGuide(title: L10n.EmptyGuide.trashTitle) {
                    EmptyGuideTile(icon: IconKit.macTrash)
                } detail: {
                    if let retentionDays {
                        EmptyGuideBullet(icon: IconKit.macClock, text: L10n.Trash.subtitle(retentionDays))
                    }
                    EmptyGuideBullet(icon: IconKit.macRestore, text: L10n.EmptyGuide.trashRestore)
                    EmptyGuideBullet(icon: IconKit.macSidebarShared, text: L10n.EmptyGuide.trashShareLinks)
                }
            case .browseRootUnassigned:
                EmptyGuide(title: L10n.EmptyGuide.browseRootUnassignedTitle) {
                    EmptyGuideTile(icon: IconKit.macSidebarBrowse)
                } detail: {
                    MacEmptyGuideMessage(message: L10n.EmptyGuide.browseRootUnassignedBody, destination: .sharedWithMe)
                }
            case let .readOnlyFolder(canDownload):
                MacReadOnlyFolderGuide(canDownload: canDownload)
            case .folderMissing:
                MacFolderMissingGuide()
            case let .serverProblem(statusCode):
                MacServerProblemGuide(statusCode: statusCode)
            case .browseRootNoVolumes:
                EmptyGuide(title: L10n.EmptyGuide.browseRootNoVolumesTitle) {
                    EmptyGuideTile(icon: IconKit.macSidebarBrowse)
                } detail: {
                    EmptyGuideBullet(icon: IconKit.macSidebarBrowse, text: L10n.EmptyGuide.browseRootVolumeFolders)
                    EmptyGuideBullet(icon: IconKit.macToolbarRefresh, text: L10n.EmptyGuide.browseRootAddFolder)
                }
            }
        }
    }

    #Preview("Shared with me") {
        MacListGuideView(guide: .sharedWithMe)
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }

    #Preview("Menu guide") {
        MacListGuideView(guide: .favorites)
            .environment(\.showMacBrowse, MacSectionOpener {})
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }

    #Preview("Menu guide, narrow, dark") {
        MacListGuideView(guide: .offline)
            .environment(\.showMacBrowse, MacSectionOpener {})
            .frame(width: 520, height: 560)
            .background(Color.macCard)
            .preferredColorScheme(.dark)
    }

    #Preview("Browse root, unassigned") {
        MacListGuideView(guide: .browseRootUnassigned)
            .environment(\.showMacSharedWithMe, MacSectionOpener {})
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }

    #Preview("Browse root, no volumes, dark") {
        MacListGuideView(guide: .browseRootNoVolumes)
            .frame(width: 900, height: 500)
            .background(Color.macCard)
            .preferredColorScheme(.dark)
    }

    #Preview("Trash") {
        MacListGuideView(guide: .trash(retentionDays: 30))
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }
#endif
