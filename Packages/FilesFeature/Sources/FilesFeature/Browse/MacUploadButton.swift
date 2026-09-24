#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Metrics {
        static let diameter: CGFloat = .superIcon
        static let glyphSize: CGFloat = .iconMedium
        static let shadowRadius: CGFloat = .space8
        static let shadowOffset: CGFloat = .space4
        static let shadowOpacity: Double = 0.25
        static let hoverScale: CGFloat = 1.06
        static let hoverDuration: Double = 0.15
    }

    /// Browse's Mac upload control: a floating accent circle in the bottom trailing corner,
    /// wrapping the same upload menu the iOS toolbar `+` opens.
    struct MacUploadButton<Content: View>: View {
        @ViewBuilder let menu: (MacUploadButtonLabel) -> Content

        var body: some View {
            menu(MacUploadButtonLabel())
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }

    struct MacUploadButtonLabel: View {
        @State private var isHovered = false

        var body: some View {
            IconKit.plus
                .font(.system(size: Metrics.glyphSize, weight: .semibold))
                // Pale gold fails contrast under white, so the glyph stays fixed dark like
                // the primary button's label.
                .foregroundStyle(Color.black)
                .frame(width: Metrics.diameter, height: Metrics.diameter)
                .background(Circle().fill(LinearGradient.accent))
                .contentShape(Circle())
                .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
                .scaleEffect(isHovered ? Metrics.hoverScale : 1)
                .animation(.easeOut(duration: Metrics.hoverDuration), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }

    #Preview("Upload button") {
        MacUploadButton { label in
            Menu {
                Button("Upload from Files") {}
            } label: {
                label
            }
        }
        .padding(.space24)
        .frame(width: 320, height: 240, alignment: .bottomTrailing)
        .backgroundGradient()
    }
#endif
