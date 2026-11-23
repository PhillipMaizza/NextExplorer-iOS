#if os(macOS)
    import SwiftUI

    public enum MacActionMenuMetrics {
        static let width: CGFloat = 250
        static let padding: CGFloat = 5
        static let rowHeight: CGFloat = 28
        static let rowRadius: CGFloat = 7
        static let rowSpacing: CGFloat = 10
        static let iconSize: CGFloat = 15
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
                content()
            }
            .padding(Metrics.padding)
            .frame(width: Metrics.width)
            .buttonStyle(.plain)
            .presentationBackground(Color.macCard)
        }
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
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
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
                        .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                        .foregroundStyle(Color.macChromeSecondary)
                }
            }
            .padding(.horizontal, Metrics.rowSpacing)
            .frame(height: Metrics.rowHeight)
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
