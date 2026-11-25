#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Metrics {
        static let rowRadius: CGFloat = .radiusControl
        static let avatarSize: CGFloat = .size32
        static let chevronSize: CGFloat = .iconSmall
        static let railAvatarSize: CGFloat = .size36
    }

    struct MacSidebarAccountLabel: View {
        let displayName: String
        let server: String?
        var isOpen = false
        @Environment(\.isMacSidebarRail) private var isRail
        @State private var isHovered = false

        var body: some View {
            if isRail {
                AvatarView(displayName: displayName, size: Metrics.railAvatarSize)
                    .frame(width: MacSidebarRail.item, height: MacSidebarRail.item)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .help([displayName, server].compactMap(\.self).joined(separator: "\n"))
            } else {
                label
            }
        }

        private var label: some View {
            HStack(spacing: .space12) {
                AvatarView(displayName: displayName, size: Metrics.avatarSize)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(displayName)
                        .type(.body2(.semibold))
                        .foregroundStyle(Color.macChromeText)
                        .lineLimit(1)
                    if let server {
                        Text(server)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.macChromeSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: .zero)
                IconKit.chevronUpDown
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                    .foregroundStyle(Color.macChromeSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
            .background(
                RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .fill(isOpen ? Color.macSelection : isHovered ? Color.macChromeButton : Color.macChromeHover)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
    }

    #Preview("Account") {
        VStack(spacing: .space8) {
            MacSidebarAccountLabel(displayName: "Phillip Maizza", server: "nextexplorer.example.com")
            MacSidebarAccountLabel(displayName: "jdoe", server: nil)
            MacSidebarAccountLabel(displayName: "Phillip Maizza", server: "nextexplorer.example.com", isOpen: true)
        }
        .padding()
        .frame(width: MacSidebarWidth.ideal)
        .background(Color.macChrome)
    }

    #Preview("Account, rail") {
        MacSidebarAccountLabel(displayName: "Phillip Maizza", server: "nextexplorer.example.com")
            .environment(\.isMacSidebarRail, true)
            .padding()
            .background(Color.macChrome)
    }
#endif
