#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Metrics {
        static let headerTop: CGFloat = .space32
        static let crumbGlyph: CGFloat = 10
        static let shadowRadius: CGFloat = 1.5
        static let shadowOffset: CGFloat = 1
    }

    enum MacPaneInset {
        static let card: CGFloat = .space16
        static let header: CGFloat = .size40
        static let section: CGFloat = .space32
        static let sectionHeader: CGFloat = .space8
        static let listGap: CGFloat = .space16
    }

    struct MacPaneHeader<Tools: View>: View {
        let title: String
        var subtitle: String?
        var crumbs: [PathCrumb] = []
        var onCrumbTapped: (PathCrumb) -> Void = { _ in }
        var inset: CGFloat = MacPaneInset.header
        var bottom: CGFloat = .zero
        @ViewBuilder var tools: () -> Tools

        var body: some View {
            HStack(spacing: .space16) {
                VStack(alignment: .leading, spacing: .space8) {
                    if !crumbs.isEmpty {
                        MacPaneCrumbs(crumbs: crumbs, onTap: onCrumbTapped)
                    }
                    Text(title)
                        .type(.display)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .type(.body2(.regular), style: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: .zero)
                tools()
            }
            .padding(.horizontal, inset)
            .padding(.top, Metrics.headerTop)
            .padding(.bottom, bottom)
        }
    }

    extension MacPaneHeader where Tools == EmptyView {
        init(
            title: String,
            subtitle: String? = nil,
            crumbs: [PathCrumb] = [],
            onCrumbTapped: @escaping (PathCrumb) -> Void = { _ in },
            inset: CGFloat = MacPaneInset.header,
            bottom: CGFloat = .zero
        ) {
            self.init(
                title: title,
                subtitle: subtitle,
                crumbs: crumbs,
                onCrumbTapped: onCrumbTapped,
                inset: inset,
                bottom: bottom
            ) { EmptyView() }
        }
    }

    struct MacPaneCrumbs: View {
        let crumbs: [PathCrumb]
        let onTap: (PathCrumb) -> Void

        var body: some View {
            HStack(spacing: .space4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        IconKit.chevronRight
                            .resizable()
                            .scaledToFit()
                            .frame(width: Metrics.crumbGlyph, height: Metrics.crumbGlyph)
                            .accessibilityHidden(true)
                    }
                    if index == crumbs.count - 1 {
                        Text(crumb.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Button(crumb.title) { onTap(crumb) }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .pointerStyle(.link)
                    }
                }
            }
            .type(.body3(.semibold), style: .secondary)
        }
    }

    struct MacPaneCard<Content: View, Tools: View>: View {
        let title: String?
        let subtitle: String?
        var reserve: CGFloat = .zero
        @ViewBuilder let content: () -> Content
        @ViewBuilder let tools: () -> Tools

        init(
            title: String?,
            subtitle: String?,
            reserve: CGFloat = .zero,
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder tools: @escaping () -> Tools
        ) {
            self.title = title
            self.subtitle = subtitle
            self.reserve = reserve
            self.content = content
            self.tools = tools
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                if let title {
                    MacPaneHeader(title: title, subtitle: subtitle, tools: tools)
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(MacSplitCardShape(reserve: reserve))
            .background(
                MacSplitCardShape(reserve: reserve)
                    .fill(Color.macCard)
                    .shadow(color: .macCardShadow, radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
            )
            .padding([.trailing, .bottom], MacPaneInset.card)
        }
    }

    extension MacPaneCard where Tools == EmptyView {
        init(
            title: String?,
            subtitle: String?,
            reserve: CGFloat = .zero,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.init(title: title, subtitle: subtitle, reserve: reserve, content: content) { EmptyView() }
        }
    }

    #Preview("Pane card") {
        MacPaneCard(title: "Thumbnails", subtitle: "Control how previews are generated.") {
            MacFormPage {
                MacFormGroup("General") {
                    MacSwitchRow("Show Hidden Files", isOn: .constant(true))
                }
            }
        } tools: {
            MacPaneSaveButton(title: "Save Changes", isSaving: false, isEnabled: true) {}
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }

    #Preview("Pane card, no subtitle") {
        MacPaneCard(title: "General", subtitle: nil) {
            MacFormPage {
                MacFormGroup("General") {
                    MacSwitchRow("Show Hidden Files", isOn: .constant(true))
                }
            }
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }

    #Preview("Header with tools") {
        MacPaneHeader(title: "Shared") {
            MacSegmentedPicker("Shared", options: ["By me", "With me"], selection: .constant("By me")) { $0 }
        }
        .frame(width: 700)
        .background(Color.macCard)
    }

    #Preview("Header with crumbs") {
        MacPaneHeader(
            title: "Documents",
            subtitle: "1 folder, 13 files",
            crumbs: FolderContentSummary.crumbs(for: "personal/Documents"),
            inset: MacPaneInset.sectionHeader,
            bottom: MacPaneInset.listGap
        )
        .frame(width: 700)
        .background(Color.macCard)
    }
#endif
