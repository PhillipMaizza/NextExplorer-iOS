#if os(macOS)
    import SwiftUI

    public enum MacActionMenuMetrics {
        static let width: CGFloat = 250
        static let padding: CGFloat = 5
        static let rowRadius: CGFloat = .radiusSmall
        static let rowSpacing: CGFloat = .space8
        public static let iconSize: CGFloat = 13
        static let chevronSize: CGFloat = 10
        static let dividerInset: CGFloat = .space8
        static let dividerSpacing: CGFloat = 5
    }

    private typealias Metrics = MacActionMenuMetrics

    public enum MacActionMenuAccessory: Equatable {
        case none
        case shortcut(String)
        case submenu
    }

    public struct MacActionMenuPanel<Content: View>: View {
        @ViewBuilder let content: () -> Content

        public init(@ViewBuilder content: @escaping () -> Content) {
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                Group(subviews: content()) { subviews in
                    ForEach(Array(subviews).separated { $0.containerValues.isMacActionMenuDivider }) { $0 }
                }
            }
            .padding(Metrics.padding)
            .frame(width: Metrics.width)
            .buttonStyle(.plain)
            .presentationBackground(Color.macCard)
        }
    }

    extension Array {
        func separated(isDivider: (Element) -> Bool) -> [Element] {
            var kept: [Element] = []
            for row in self where !isDivider(row) || kept.last.map(isDivider) == false {
                kept.append(row)
            }
            while let last = kept.last, isDivider(last) {
                kept.removeLast()
            }
            return kept
        }
    }

    extension ContainerValues {
        @Entry var isMacActionMenuDivider = false
        @Entry var macActionMenuItem: MacActionMenuItem?
    }

    public struct MacActionMenuRow: View {
        let title: String
        let icon: Image
        var accessory = MacActionMenuAccessory.none
        var isDestructive = false
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        public init(
            _ title: String,
            icon: Image,
            accessory: MacActionMenuAccessory = .none,
            isDestructive: Bool = false
        ) {
            self.title = title
            self.icon = icon
            self.accessory = accessory
            self.isDestructive = isDestructive
        }

        public var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .macSquare(Metrics.iconSize)
                    .foregroundStyle(isDestructive ? Color.negativeText : Color.macChromeSecondary)
                Text(title)
                    .type(.body2(.regular))
                    .foregroundStyle(isDestructive ? Color.negativeText : Color.primaryDS)
                    .lineLimit(1)
                Spacer(minLength: .space12)
                switch accessory {
                case .none:
                    EmptyView()
                case let .shortcut(keys):
                    Text(keys)
                        .type(.body3(.regular), style: .secondary)
                case .submenu:
                    IconKit.chevronRight
                        .resizable()
                        .scaledToFit()
                        .macSquare(Metrics.chevronSize)
                        .foregroundStyle(Color.macChromeSecondary)
                }
            }
            .padding(.horizontal, Metrics.rowSpacing)
            .macMinHeight(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .fill(isHovered && isEnabled ? Color.macSelection : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : MacOpacity.disabled)
            .onHover { isHovered = $0 }
        }
    }

    public struct MacActionMenuButton: View {
        let title: String
        let icon: Image
        var accessory = MacActionMenuAccessory.none
        var isDestructive = false
        let action: () -> Void
        @Environment(\.dismiss) private var dismiss

        public init(
            _ title: String,
            icon: Image,
            accessory: MacActionMenuAccessory = .none,
            isDestructive: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.accessory = accessory
            self.isDestructive = isDestructive
            self.action = action
        }

        public var body: some View {
            Button {
                dismiss()
                action()
            } label: {
                MacActionMenuRow(title, icon: icon, accessory: accessory, isDestructive: isDestructive)
            }
            .buttonStyle(.plain)
            .containerValue(\.macActionMenuItem, MacActionMenuItem(title: title, icon: icon, action: action))
        }
    }

    public struct MacActionMenuItem {
        public let title: String
        public let icon: Image
        public let action: () -> Void
    }

    public struct MacActionMenuSoleItem<Content: View, Single: View, Many: View>: View {
        private let content: () -> Content
        private let single: (MacActionMenuItem) -> Single
        private let many: () -> Many

        public init(
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder single: @escaping (MacActionMenuItem) -> Single,
            @ViewBuilder many: @escaping () -> Many
        ) {
            self.content = content
            self.single = single
            self.many = many
        }

        public var body: some View {
            Group(subviews: content()) { subviews in
                let rows = subviews.filter { !$0.containerValues.isMacActionMenuDivider }
                if rows.count == 1, let item = rows[0].containerValues.macActionMenuItem {
                    single(item)
                } else {
                    many()
                }
            }
        }
    }

    public struct MacActionMenuDivider: View {
        public init() {}

        public var body: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
                .padding(.horizontal, Metrics.dividerInset)
                .padding(.vertical, Metrics.dividerSpacing)
                .containerValue(\.isMacActionMenuDivider, true)
        }
    }

    #Preview("Action menu") {
        MacActionMenuPanel {
            MacActionMenuButton("Open With", icon: IconKit.openInApp, accessory: .submenu) {}
            MacActionMenuButton("Download", icon: IconKit.download) {}
            MacActionMenuButton("Keep Offline", icon: IconKit.availableOffline) {}
            MacActionMenuDivider()
            MacActionMenuButton("Rename…", icon: IconKit.rename, accessory: .shortcut("↵")) {}
            MacActionMenuButton("Duplicate", icon: IconKit.duplicate, accessory: .shortcut("⌘D")) {}
            MacActionMenuButton("Compress", icon: IconKit.archiveDocument) {}.disabled(true)
            MacActionMenuDivider()
            MacActionMenuButton(
                "Move to Trash",
                icon: IconKit.delete,
                accessory: .shortcut("⌘⌫"),
                isDestructive: true
            ) {}
        }
        .background(Color.macCard)
    }
#endif
