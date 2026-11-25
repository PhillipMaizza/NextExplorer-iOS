#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileIconRatio: CGFloat = 0.4375
        static let tileTint: Double = .opacityWash
        static let bulletIconSize: CGFloat = .size18
        static let bulletIconNudge: CGFloat = 1
        static let highlightTint: Double = .opacitySelection
        static let menuWidth: CGFloat = 220
    }

    @MainActor
    final class MacBrowseOpener {
        private let open: () -> Void

        init(_ open: @escaping () -> Void) {
            self.open = open
        }

        func callAsFunction() {
            open()
        }
    }

    extension EnvironmentValues {
        @Entry var showMacBrowse: MacBrowseOpener?
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
        let message: String
        var showsBrowseButton = true
        @Environment(\.showMacBrowse) private var showBrowse

        var body: some View {
            Text(message)
                .type(.body1(.regular), style: .secondary)
            if showsBrowseButton, let showBrowse {
                Button(L10n.EmptyGuide.goToBrowse) { showBrowse() }
                    .buttonStyle(.macDS(.primary))
                    .padding(.top, .space4)
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
            HStack(alignment: .top, spacing: .space8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.bulletIconSize, height: Metrics.bulletIconSize)
                    .foregroundStyle(Color.secondaryDS)
                    .padding(.top, Metrics.bulletIconNudge)
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
                    MacEmptyGuideMessage(message: L10n.Shared.emptyWithMe, showsBrowseButton: false)
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
            .environment(\.showMacBrowse, MacBrowseOpener {})
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }

    #Preview("Menu guide, narrow, dark") {
        MacListGuideView(guide: .offline)
            .environment(\.showMacBrowse, MacBrowseOpener {})
            .frame(width: 520, height: 560)
            .background(Color.macCard)
            .preferredColorScheme(.dark)
    }

    #Preview("Trash") {
        MacListGuideView(guide: .trash(retentionDays: 30))
            .frame(width: 900, height: 500)
            .background(Color.macCard)
    }
#endif
