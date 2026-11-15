#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let logoSize: CGFloat = 24
        /// Padding of the About button's hover pill, taken from the header's own edge so the logo
        /// lines up with the row glyphs below.
        static let aboutHoverInset: CGFloat = .space8
        static let horizontalPadding: CGFloat = .space16
    }

    /// The top of the Mac sidebar, under the window buttons: the app's logo and name, which open
    /// the About window.
    struct MacSidebarHeader: View {
        @Environment(\.openWindow) private var openWindow
        @State private var isHovered = false

        var body: some View {
            Button {
                openWindow(id: MacAboutView.windowID)
            } label: {
                HStack(spacing: .space8) {
                    IconKit.logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.logoSize, height: Constants.logoSize)
                        .accessibilityHidden(true)
                    Text(AppIdentity.name)
                        .type(.headline4, style: .primaryOnSurface)
                        .lineLimit(1)
                }
                .padding(.horizontal, Constants.aboutHoverInset)
                .padding(.vertical, .space4)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(isHovered ? Color.primaryDS.opacity(MacSidebarMetrics.hoverOpacity) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(L10n.Menu.about)
            .accessibilityLabel(L10n.Menu.about)
            .fixedSize()
            .padding(.leading, Constants.horizontalPadding - Constants.aboutHoverInset)
            .frame(maxWidth: .infinity, minHeight: MacSidebarMetrics.linkRowHeight, alignment: .leading)
            .padding(.bottom, .space24)
        }
    }

    #Preview {
        MacSidebarHeader().frame(width: 260)
    }
#endif
