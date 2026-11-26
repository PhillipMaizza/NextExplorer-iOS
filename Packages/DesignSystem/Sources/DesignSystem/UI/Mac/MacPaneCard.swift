#if os(macOS)
    import SwiftUI

    private enum Metrics {
        static let headerTop: CGFloat = .space32
        static let crumbGlyph: CGFloat = 10
        static let shadowRadius: CGFloat = 1.5
        static let shadowOffset: CGFloat = 1
    }

    public enum MacPaneInset {
        public static let card: CGFloat = .space16
        public static let header: CGFloat = .size40
        public static let section: CGFloat = .space32
        public static let sectionHeader: CGFloat = .space8
        public static let listGap: CGFloat = .space16
    }

    public struct MacPaneHeader<Tools: View>: View {
        private let title: String
        private let subtitle: String?
        private let crumbs: [PathCrumb]
        private let onCrumbTapped: (PathCrumb) -> Void
        private let inset: CGFloat
        private let bottom: CGFloat
        private let tools: () -> Tools

        public init(
            title: String,
            subtitle: String? = nil,
            crumbs: [PathCrumb] = [],
            onCrumbTapped: @escaping (PathCrumb) -> Void = { _ in },
            inset: CGFloat = MacPaneInset.header,
            bottom: CGFloat = .zero,
            @ViewBuilder tools: @escaping () -> Tools
        ) {
            self.title = title
            self.subtitle = subtitle
            self.crumbs = crumbs
            self.onCrumbTapped = onCrumbTapped
            self.inset = inset
            self.bottom = bottom
            self.tools = tools
        }

        public var body: some View {
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

    public extension MacPaneHeader where Tools == EmptyView {
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

    public struct MacPaneCrumbs: View {
        private let crumbs: [PathCrumb]
        private let onTap: (PathCrumb) -> Void

        public init(crumbs: [PathCrumb], onTap: @escaping (PathCrumb) -> Void) {
            self.crumbs = crumbs
            self.onTap = onTap
        }

        public var body: some View {
            HStack(spacing: .space4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        IconKit.chevronRight
                            .resizable()
                            .scaledToFit()
                            .macSquare(Metrics.crumbGlyph)
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

    public struct MacPaneCard<Content: View, Tools: View>: View {
        private let title: String?
        private let subtitle: String?
        private let reserve: CGFloat
        private let content: () -> Content
        private let tools: () -> Tools

        public init(
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

        public var body: some View {
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

    public extension MacPaneCard where Tools == EmptyView {
        init(
            title: String?,
            subtitle: String?,
            reserve: CGFloat = .zero,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.init(title: title, subtitle: subtitle, reserve: reserve, content: content) { EmptyView() }
        }
    }

    public struct MacSplitCardShape: Shape {
        public var reserve: CGFloat

        public init(reserve: CGFloat) {
            self.reserve = reserve
        }

        public var animatableData: CGFloat {
            get { reserve }
            set { reserve = newValue }
        }

        public func path(in rect: CGRect) -> Path {
            let radius = CGFloat.radiusCard
            var path = Path()
            guard reserve > .zero else {
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
                return path
            }
            let mainWidth = max(.zero, rect.width - reserve)
            let side = rect.width - mainWidth - MacInspectorMetrics.gap
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: mainWidth, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
            if side > .zero {
                path.addRoundedRect(
                    in: CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: rect.height),
                    cornerSize: CGSize(width: radius, height: radius),
                    style: .continuous
                )
            }
            return path
        }
    }

    #Preview("Pane card") {
        MacPaneCard(title: "Thumbnails", subtitle: "Control how previews are generated.") {
            MacFormPage {
                MacFormGroup("General") {
                    MacFormRow("Show Hidden Files") { Toggle("Show Hidden Files", isOn: .constant(true)).labelsHidden()
                    }
                }
            }
        } tools: {
            Button("Save Changes") {}.buttonStyle(.macDS(.primary))
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }

    #Preview("Pane card, no subtitle, split") {
        MacPaneCard(title: "General", subtitle: nil, reserve: MacInspectorMetrics.reserve) {
            MacFormPage {
                MacFormGroup("General") {
                    MacFormRow("Show Hidden Files") { Toggle("Show Hidden Files", isOn: .constant(true)).labelsHidden()
                    }
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

    #Preview("Header with crumbs, largest text") {
        MacPaneHeader(
            title: "Documents",
            subtitle: "1 folder, 13 files",
            crumbs: [PathCrumb(title: "Browse", path: ""), PathCrumb(title: "Documents", path: "Documents")],
            inset: MacPaneInset.sectionHeader,
            bottom: MacPaneInset.listGap
        )
        .frame(width: 700)
        .background(Color.macCard)
        .macTextScale(MacTextScale.range.upperBound)
    }
#endif
