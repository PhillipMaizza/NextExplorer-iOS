#if os(macOS)
    import AppStorageKeys
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileIconRatio: CGFloat = 0.4375
        static let tileTint: Double = .opacityWash
        static let bulletIconSize: CGFloat = .size16
        static let bulletIconBaselineDrop: CGFloat = 5
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
        @Entry var canOpenMacAccessRules = false
    }

    struct MacEmptyGuideKey: PreferenceKey {
        static let defaultValue: MacListGuide? = nil

        static func reduce(value: inout MacListGuide?, nextValue: () -> MacListGuide?) {
            value = value ?? nextValue()
        }
    }

    extension View {
        func macEmptyGuide(_ guide: MacListGuide?) -> some View {
            preference(key: MacEmptyGuideKey.self, value: guide)
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

    struct MacEmptyGuide<Art: View, Detail: View>: View {
        let title: String
        @ViewBuilder let art: () -> Art
        @ViewBuilder let detail: () -> Detail

        var body: some View {
            HStack(spacing: .space48) {
                art()
                VStack(alignment: .leading, spacing: .space12) {
                    Text(title)
                        .type(.headline2)
                        .foregroundStyle(Color.primaryDS)
                    detail()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.space40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    struct MacEmptyGuideTile: View {
        let icon: Image
        var size: CGFloat = .size96

        var body: some View {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: size * Metrics.tileIconRatio, height: size * Metrics.tileIconRatio)
                .foregroundStyle(Color.accentText)
                .frame(width: size, height: size)
                .background(
                    Color.accent.opacity(Metrics.tileTint),
                    in: RoundedRectangle(cornerRadius: size * .tileCornerRatio, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    struct MacEmptyGuideBullet: View {
        let icon: Image
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: .space8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.bulletIconSize, height: Metrics.bulletIconSize)
                    .foregroundStyle(Color.secondaryDS)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.bulletIconBaselineDrop
                    }
                    .accessibilityHidden(true)
                Text(text)
                    .type(.body1(.regular), style: .secondary)
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
            MacEmptyGuide(title: title) {
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
            MacEmptyGuide(title: L10n.EmptyGuide.readOnlyTitle) {
                MacEmptyGuideTile(icon: IconKit.macLock)
            } detail: {
                MacEmptyGuideBullet(
                    icon: IconKit.macEye,
                    text: canDownload ? L10n.EmptyGuide.readOnlyOpen : L10n.EmptyGuide.readOnlyOpenOnly
                )
                MacEmptyGuideBullet(icon: IconKit.macLock, text: L10n.EmptyGuide.readOnlyLocked)
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
        let guide: MacListGuide

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
                MacEmptyGuide(title: L10n.EmptyGuide.sharedWithMeTitle) {
                    MacEmptyGuideTile(icon: IconKit.macSidebarShared)
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
                MacEmptyGuide(title: L10n.EmptyGuide.trashTitle) {
                    MacEmptyGuideTile(icon: IconKit.macTrash)
                } detail: {
                    if let retentionDays {
                        MacEmptyGuideBullet(icon: IconKit.macClock, text: L10n.Trash.subtitle(retentionDays))
                    }
                    MacEmptyGuideBullet(icon: IconKit.macRestore, text: L10n.EmptyGuide.trashRestore)
                    MacEmptyGuideBullet(icon: IconKit.macSidebarShared, text: L10n.EmptyGuide.trashShareLinks)
                }
            case .browseRootUnassigned:
                MacEmptyGuide(title: L10n.EmptyGuide.browseRootUnassignedTitle) {
                    MacEmptyGuideTile(icon: IconKit.macSidebarBrowse)
                } detail: {
                    MacEmptyGuideMessage(message: L10n.EmptyGuide.browseRootUnassignedBody, destination: .sharedWithMe)
                }
            case let .readOnlyFolder(canDownload):
                MacReadOnlyFolderGuide(canDownload: canDownload)
            case .browseRootNoVolumes:
                MacEmptyGuide(title: L10n.EmptyGuide.browseRootNoVolumesTitle) {
                    MacEmptyGuideTile(icon: IconKit.macSidebarBrowse)
                } detail: {
                    MacEmptyGuideBullet(icon: IconKit.macSidebarBrowse, text: L10n.EmptyGuide.browseRootVolumeFolders)
                    MacEmptyGuideBullet(icon: IconKit.macToolbarRefresh, text: L10n.EmptyGuide.browseRootAddFolder)
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
