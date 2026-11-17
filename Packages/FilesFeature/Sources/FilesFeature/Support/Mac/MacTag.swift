#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Constants {
        /// The fill of a tag, a wash of its color.
        static let washOpacity: Double = 0.25
    }

    /// A small rounded tag in a wash of a color, such as a row's ⌘ number, the app version or the
    /// search field's shortcut.
    struct MacTag: View {
        let text: String
        var tint: Color = .tertiaryDS
        var style: Typography.TextStyle = .tertiary

        var body: some View {
            Text(text)
                .type(.caption(.regular), style: style)
                .padding(.horizontal, .space4)
                .padding(.vertical, .space2)
                .background(
                    RoundedRectangle(cornerRadius: .radiusXSmall, style: .continuous)
                        .fill(tint.opacity(Constants.washOpacity))
                )
                .accessibilityHidden(true)
        }
    }

    #Preview {
        HStack {
            MacTag(text: "\u{2318} 4")
            MacTag(text: "1.2.0", tint: .accent, style: .link)
        }
        .padding()
    }
#endif
