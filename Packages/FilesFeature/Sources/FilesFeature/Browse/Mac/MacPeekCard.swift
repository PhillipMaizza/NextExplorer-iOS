#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacPeekMetrics {
        static let maxWidth: CGFloat = 880
        static let maxHeight: CGFloat = 760
        static let margin: CGFloat = .space32
        static let radius: CGFloat = .radiusLarge
        static let iconSize: CGFloat = .size40
        static let columns = 4
        static let tileAspect: CGFloat = 4.0 / 3.0
        static let dimmedOpacity: Double = 0.6
        static let previewWidth: CGFloat = 840
        static let previewHeight: CGFloat = 560
        static let shadowOpacity: Double = 0.35
        static let shadowRadius: CGFloat = 45
        static let shadowOffset: CGFloat = 30
        static let scrimDarkOpacity: Double = 0.55
        static let scrimLightOpacity: Double = 0.28
        static let zoomScale: CGFloat = 0.94
        static let separator = " \u{00B7} "
    }

    struct MacPeekCard<More: View>: View {
        let item: FileItem
        let subtitle: String
        let position: String
        let serverURL: URL
        let isSavedOffline: Bool
        let shouldShowThumbnails: Bool
        let showsHiddenFiles: Bool
        let onOpen: (() -> Void)?
        let onShare: (() -> Void)?
        let onStep: (Int) -> Void
        let onClose: () -> Void
        var showsMore = true
        @ViewBuilder let more: () -> More

        @FocusState private var isFocused: Bool
        @State private var isMoreOpen = false
        @State private var folderSummary: String?

        var body: some View {
            VStack(spacing: .zero) {
                header
                MacPeekSeparator()
                MacPeekContent(
                    item: item,
                    serverURL: serverURL,
                    isSavedOffline: isSavedOffline,
                    shouldShowThumbnails: shouldShowThumbnails,
                    showsHiddenFiles: showsHiddenFiles
                )
                .onPreferenceChange(MacPeekFolderSummaryKey.self) { folderSummary = $0 }
                MacPeekSeparator()
                footer
            }
            .macPeekCardChrome()
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(.space) {
                onClose()
                return .handled
            }
            .onKeyPress(.upArrow) {
                onStep(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                onStep(1)
                return .handled
            }
            .onKeyPress(.return) {
                guard let onOpen else { return .ignored }
                onOpen()
                return .handled
            }
            .onExitCommand {
                if isMoreOpen {
                    isMoreOpen = false
                } else {
                    onClose()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(item.name)
            .accessibilityIdentifier(AccessibilityIdentifiers.Browse.peekCard)
        }

        private var header: some View {
            HStack(spacing: .space12) {
                MacFileTile(
                    item: item,
                    serverURL: serverURL,
                    size: MacPeekMetrics.iconSize,
                    shouldShowPlayBadge: false
                )
                VStack(alignment: .leading, spacing: .space2) {
                    Text(item.name)
                        .type(.subtitle2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onOpen {
                    Button(L10n.Browse.open, action: onOpen)
                        .buttonStyle(.macDS(.primary, size: .small))
                }
                if let onShare {
                    MacIconButton(IconKit.link, label: L10n.Common.share, action: onShare)
                }
                if showsMore {
                    MacActionMenuSoleItem(content: more) { item in
                        MacIconButton(item.icon, label: item.title, action: item.action)
                    } many: {
                        MacIconButton(IconKit.ellipsis, label: L10n.Common.more) { isMoreOpen.toggle() }
                            .popover(isPresented: $isMoreOpen, arrowEdge: .bottom) {
                                MacActionMenuPanel(content: more)
                            }
                    }
                }
                MacIconButton(IconKit.close, label: L10n.Common.close, action: onClose)
            }
            .padding(.leading, .space24)
            .padding(.trailing, .space16)
            .padding(.vertical, .space16)
        }

        private var footer: some View {
            HStack(spacing: .space16) {
                Text([position, folderSummary].compactMap(\.self).joined(separator: " · "))
                    .type(.caption(.regular), style: .secondary)
                    .monospacedDigit()
                Spacer(minLength: .zero)
                MacPeekHint(key: MacShortcutHint.space, title: L10n.Common.close)
                MacPeekHint(key: MacShortcutHint.arrows, title: L10n.Spotlight.hintMove)
                if onOpen != nil {
                    MacPeekHint(key: MacShortcutHint.enter, title: L10n.Spotlight.hintOpen)
                }
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, .space12)
        }
    }

    struct MacPeekSeparator: View {
        var body: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
        }
    }

    struct MacPeekHint: View {
        let key: String
        let title: String

        var body: some View {
            HStack(spacing: .space4) {
                MacKeyHint(key)
                Text(title).type(.caption(.regular), style: .secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private struct MacPeekCardChrome: ViewModifier {
        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MacPeekMetrics.radius, style: .continuous)
        }

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: MacPeekMetrics.maxWidth, maxHeight: MacPeekMetrics.maxHeight)
                .background(Color.macCard, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.macLine))
                .shadow(
                    color: .black.opacity(MacPeekMetrics.shadowOpacity),
                    radius: MacPeekMetrics.shadowRadius,
                    y: MacPeekMetrics.shadowOffset
                )
        }
    }

    extension View {
        func macPeekCardChrome() -> some View {
            modifier(MacPeekCardChrome())
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let file = FileItem(
            name: "Product Brochure.pdf",
            path: "Documents",
            dateModified: .distantPast,
            size: 1_200_000,
            kind: "pdf"
        )
        static let folder = FileItem(
            name: "Contracts",
            path: "Documents",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )

        @MainActor
        static func card(_ item: FileItem, subtitle: String, canShare: Bool = true) -> some View {
            MacPeekCard(
                item: item,
                subtitle: subtitle,
                position: "3 of 14",
                serverURL: serverURL,
                isSavedOffline: false,
                shouldShowThumbnails: true,
                showsHiddenFiles: false,
                onOpen: {},
                onShare: canShare ? {} : nil,
                onStep: { _ in },
                onClose: {}
            ) {
                MacActionMenuButton(L10n.Common.share, icon: IconKit.link) {}
            }
            .padding(MacPeekMetrics.margin)
            .frame(width: 960, height: 820)
            .background(Color.macChrome)
        }
    }

    #Preview("File") {
        PreviewFixture.card(PreviewFixture.file, subtitle: "PDF · 1.2 MB")
    }

    #Preview("Folder") {
        PreviewFixture.card(PreviewFixture.folder, subtitle: "Folder · 48 MB")
    }

    #Preview("Read only") {
        PreviewFixture.card(PreviewFixture.file, subtitle: "PDF · 1.2 MB", canShare: false)
    }
#endif
