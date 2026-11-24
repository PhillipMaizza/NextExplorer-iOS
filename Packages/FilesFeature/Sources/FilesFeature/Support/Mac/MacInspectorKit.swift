#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacInspectorMetrics {
        static let width: CGFloat = 340
        static let gap: CGFloat = .space12
        static let padding: CGFloat = 22
        static let sectionSpacing: CGFloat = 22
        static let rowHeight: CGFloat = .size44
        static let tileHeight: CGFloat = 62
        static let closeSize: CGFloat = 30
        static let pictureScrimOpacity: Double = 0.55
        static let pictureHeight: CGFloat = 250
        static let followDelay: Duration = .milliseconds(200)
        static let reserve = width + gap
    }

    struct MacInspectorReserveKey: PreferenceKey {
        static let defaultValue: CGFloat = .zero

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    struct MacSplitCardShape: Shape {
        var reserve: CGFloat

        var animatableData: CGFloat {
            get { reserve }
            set { reserve = newValue }
        }

        func path(in rect: CGRect) -> Path {
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

    extension View {
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

    enum MacInspectorLocation {
        static func parent(of item: FileItem) -> String {
            (item.id as NSString).deletingLastPathComponent
        }

        static func title(parent: String) -> String {
            PersonalSpace.folderTitle(parent)
        }

        static func trail(parent: String) -> String {
            parent.isEmpty ? PersonalSpace.folderTitle(parent) : PersonalSpace.trail(parent)
        }
    }

    public struct MacInspectorAction {
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var closeMacInspector: MacInspectorAction?
        @Entry var openMacInspector: MacInspectorAction?
    }

    struct MacInspectorGroup<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
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

    struct MacInspectorRow: View {
        let label: String
        let value: String
        var icon: Image?
        var valueLineLimit = 1
        var valueColor = Color.primaryDS

        init(
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

        var body: some View {
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
            .frame(minHeight: MacInspectorMetrics.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }

    struct MacInspectorSectionHeader: View {
        let title: String
        var count: Int?
        var actionTitle: String?
        var isDestructive = false
        var action: (() -> Void)?

        var body: some View {
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

    struct MacInspectorQuickAction: Identifiable {
        enum Kind {
            case open, share, favorite, download
        }

        let id: Kind
        let icon: Image
        let title: String
        var isOn = false
        var isEnabled = true
        let action: () -> Void
    }

    struct MacInspectorQuickActions<More: View>: View {
        let actions: [MacInspectorQuickAction]
        var showsMore = false
        @ViewBuilder let more: () -> More
        @State private var isMoreOpen = false

        var body: some View {
            HStack(spacing: .space8) {
                ForEach(actions) { action in
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
                    .frame(width: .iconSmall, height: .iconSmall)
                    .foregroundStyle(isOn ? Color.accentText : Color.primaryDS)
                Text(title)
                    .type(.caption(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: MacInspectorMetrics.tileHeight)
            .macGroupedRows()
            .contentShape(Rectangle())
        }
    }

    extension MacInspectorQuickActions where More == EmptyView {
        init(actions: [MacInspectorQuickAction]) {
            self.init(actions: actions) { EmptyView() }
        }
    }

    struct MacInspectorCloseButton: View {
        var isOnPicture = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .frame(width: .iconXSmall, height: .iconXSmall)
                    .foregroundStyle(isOnPicture ? Color.white : Color.secondaryDS)
                    .frame(width: MacInspectorMetrics.closeSize, height: MacInspectorMetrics.closeSize)
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
                MacInspectorQuickAction(id: .open, icon: IconKit.document, title: "Open") {},
                MacInspectorQuickAction(id: .share, icon: IconKit.link, title: "Share") {},
                MacInspectorQuickAction(id: .favorite, icon: IconKit.star, title: "Favorite", isOn: true) {},
            ], showsMore: true) {
                MacActionMenuButton("Rename…", icon: IconKit.pencil) {}
            }
            MacInspectorGroup {
                MacInspectorRow("Kind", "PDF")
                MacInspectorRow("Size", "2.4 MB")
                MacInspectorRow("Modified", "Nov 13, 2026")
            }
            MacInspectorSectionHeader(title: "Versions", count: 2, actionTitle: "Delete All", isDestructive: true) {}
            MacInspectorCloseButton {}
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
