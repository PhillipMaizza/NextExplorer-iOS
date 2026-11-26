#if os(macOS)
    import Localization
    import SwiftUI

    public enum MacInspectorMetrics {
        public static let width: CGFloat = 340
        public static let gap: CGFloat = .space12
        public static let padding: CGFloat = .space24
        public static let sectionSpacing: CGFloat = .space24
        public static let rowHeight: CGFloat = MacControlHeight.xLarge.points
        public static let tileHeight: CGFloat = 62
        public static let closeSize: CGFloat = 30
        public static let pictureScrimOpacity: Double = 0.55
        public static let pictureHeight: CGFloat = 250
        public static let followDelay: Duration = .milliseconds(200)
        public static let reserve = width + gap
    }

    public struct MacInspectorReserveKey: PreferenceKey {
        public static let defaultValue: CGFloat = .zero

        public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    public extension View {
        func macInspectorColumn() -> some View {
            frame(width: MacInspectorMetrics.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    Color.macCard,
                    in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                )
                .padding(.leading, MacPaneInset.section + MacInspectorMetrics.gap)
                .padding(.trailing, -MacPaneInset.section)
                .preference(key: MacInspectorReserveKey.self, value: MacInspectorMetrics.reserve)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    public struct MacInspectorGroup<Content: View>: View {
        private let content: () -> Content

        public init(@ViewBuilder content: @escaping () -> Content) {
            self.content = content
        }

        public var body: some View {
            Group(subviews: content()) { rows in
                VStack(spacing: .zero) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.macLine)
                                .frame(height: .borderWidthHairline)
                        }
                    }
                }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space2)
            .macGroupedRows()
        }
    }

    public struct MacInspectorRow: View {
        private let label: String
        private let value: String
        private let icon: Image?
        private let valueLineLimit: Int
        private let valueColor: Color

        public init(
            _ label: String,
            _ value: String,
            icon: Image? = nil,
            valueLineLimit: Int = 1,
            valueColor: Color = Color.primaryDS
        ) {
            self.label = label
            self.value = value
            self.icon = icon
            self.valueLineLimit = valueLineLimit
            self.valueColor = valueColor
        }

        public var body: some View {
            HStack(spacing: .space12) {
                Text(label)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize()
                Spacer(minLength: .space8)
                if let icon {
                    icon.foregroundStyle(Color.accent).accessibilityHidden(true)
                }
                Text(value)
                    .type(.body3(.regular))
                    .foregroundStyle(valueColor)
                    .lineLimit(valueLineLimit)
                    .multilineTextAlignment(.trailing)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.vertical, valueLineLimit > 1 ? .space8 : .zero)
            .macMinHeight(points: MacInspectorMetrics.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }

    public struct MacInspectorSectionHeader: View {
        private let title: String
        private let count: Int?
        private let actionTitle: String?
        private let isDestructive: Bool
        private let action: (() -> Void)?

        public init(
            title: String,
            count: Int? = nil,
            actionTitle: String? = nil,
            isDestructive: Bool = false,
            action: (() -> Void)? = nil
        ) {
            self.title = title
            self.count = count
            self.actionTitle = actionTitle
            self.isDestructive = isDestructive
            self.action = action
        }

        public var body: some View {
            HStack(spacing: .space8) {
                Text(title)
                    .type(.body2(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let count {
                    MacChip(text: count.formatted(), tone: .gray, size: .small)
                }
                Spacer(minLength: .zero)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .type(.body3(.semibold))
                        .foregroundStyle(isDestructive ? Color.negativeText : Color.accentText)
                }
            }
        }
    }

    public struct MacInspectorQuickAction {
        let icon: Image
        let title: String
        let isOn: Bool
        let isEnabled: Bool
        let action: () -> Void

        public init(
            icon: Image,
            title: String,
            isOn: Bool = false,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.title = title
            self.isOn = isOn
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    public struct MacInspectorQuickActions<More: View>: View {
        private let actions: [MacInspectorQuickAction]
        private let showsMore: Bool
        private let more: () -> More
        @State private var isMoreOpen = false

        public init(
            actions: [MacInspectorQuickAction],
            showsMore: Bool = false,
            @ViewBuilder more: @escaping () -> More
        ) {
            self.actions = actions
            self.showsMore = showsMore
            self.more = more
        }

        public var body: some View {
            HStack(spacing: .space8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action: action.action) {
                        tile(icon: action.icon, title: action.title, isOn: action.isOn)
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                    .accessibilityAddTraits(action.isOn ? .isSelected : [])
                }
                if showsMore {
                    Button { isMoreOpen.toggle() } label: {
                        tile(icon: IconKit.ellipsis, title: L10n.Common.more, isOn: isMoreOpen)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isMoreOpen, arrowEdge: .bottom) {
                        MacActionMenuPanel(content: more)
                    }
                }
            }
        }

        private func tile(icon: Image, title: String, isOn: Bool) -> some View {
            VStack(spacing: .space8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .macSquare(.iconSmall)
                    .foregroundStyle(isOn ? Color.accentText : Color.primaryDS)
                Text(title)
                    .type(.body3(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .macMinHeight(points: MacInspectorMetrics.tileHeight)
            .macGroupedRows()
            .contentShape(Rectangle())
        }
    }

    public extension MacInspectorQuickActions where More == EmptyView {
        init(actions: [MacInspectorQuickAction]) {
            self.init(actions: actions) { EmptyView() }
        }
    }

    public struct MacInspectorCloseButton: View {
        private let isOnPicture: Bool
        private let action: () -> Void

        public init(isOnPicture: Bool = false, action: @escaping () -> Void) {
            self.isOnPicture = isOnPicture
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .macSquare(.iconXSmall)
                    .foregroundStyle(isOnPicture ? Color.white : Color.secondaryDS)
                    .macSquare(MacInspectorMetrics.closeSize)
                    .background(Circle().fill(isOnPicture
                            ? Color.black.opacity(MacInspectorMetrics.pictureScrimOpacity)
                            : Color.macRow))
                        .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(L10n.Common.close)
        }
    }

    #Preview("Inspector kit") {
        VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
            MacInspectorQuickActions(actions: [
                MacInspectorQuickAction(icon: IconKit.document, title: "Open") {},
                MacInspectorQuickAction(icon: IconKit.link, title: "Share") {},
                MacInspectorQuickAction(icon: IconKit.star, title: "Favorite", isOn: true) {},
                MacInspectorQuickAction(icon: IconKit.download, title: "Download", isEnabled: false) {},
            ], showsMore: true) {
                MacActionMenuButton("Rename…", icon: IconKit.pencil) {}
            }
            MacInspectorGroup {
                MacInspectorRow("Kind", "PDF")
                MacInspectorRow("Size", "2.4 MB")
                MacInspectorRow("Where", "personal/Documents/Reports/2026", valueLineLimit: 2)
            }
            MacInspectorSectionHeader(title: "Versions", count: 2, actionTitle: "Delete All", isDestructive: true) {}
            HStack {
                MacInspectorCloseButton {}
                MacInspectorCloseButton(isOnPicture: true) {}
                    .padding(.space8)
                    .background(Color.gray)
            }
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }

    #Preview("Inspector kit, largest text") {
        MacInspectorGroup {
            MacInspectorRow("Kind", "PDF")
            MacInspectorRow("Size", "2.4 MB")
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
        .macTextScale(MacTextScale.range.upperBound)
    }
#endif
