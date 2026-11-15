#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacSidebarMetrics {
        /// The height of every sidebar row, before the pill's own vertical inset.
        static let linkRowHeight: CGFloat = 36
        static let rowHorizontalPadding: CGFloat = .space8
        static let hoverOpacity: Double = 0.08
        static let selectedOpacity: Double = 0.14
        static let selectionVerticalInset: CGFloat = 1
        /// One glyph column for every row, so the titles line up.
        static let iconColumnWidth: CGFloat = 22
        static let labelSpacing: CGFloat = .space8
    }

    /// A sidebar row on the frosted Mac sidebar: a glyph and a title in a pill that shows hover and
    /// selection, the same for the sections, the footer links and Settings.
    struct MacSidebarLinkRow: View {
        let title: String
        let icon: Image
        var isSelected = false
        var showsNewFilesDot = false
        let action: () -> Void

        @State private var isHovered = false

        private var pillFill: Color {
            if isSelected {
                Color.primaryDS.opacity(MacSidebarMetrics.selectedOpacity)
            } else if isHovered {
                Color.primaryDS.opacity(MacSidebarMetrics.hoverOpacity)
            } else {
                .clear
            }
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: MacSidebarMetrics.labelSpacing) {
                    MacSidebarIcon(image: icon)
                        .frame(width: MacSidebarMetrics.iconColumnWidth)
                    Text(title)
                        .lineLimit(1)
                    if showsNewFilesDot {
                        Spacer(minLength: 0)
                        NewFilesDot()
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, MacSidebarMetrics.rowHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: MacSidebarMetrics.linkRowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(pillFill)
                        .padding(.vertical, MacSidebarMetrics.selectionVerticalInset)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel(title)
            // The dot reads as the row's value, as it does on the tab bar, not as part of its name.
            .accessibilityValue(showsNewFilesDot ? L10n.Offline.newFilesBadge : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    #Preview("Rows") {
        VStack(spacing: .space4) {
            MacSidebarLinkRow(title: "Browse", icon: IconKit.folder, isSelected: true) {}
            MacSidebarLinkRow(title: "Offline", icon: IconKit.availableOffline, showsNewFilesDot: true) {}
            MacSidebarLinkRow(title: "Settings", icon: IconKit.gearshape) {}
        }
        .padding(.space8)
        .frame(width: 260)
    }
#endif
