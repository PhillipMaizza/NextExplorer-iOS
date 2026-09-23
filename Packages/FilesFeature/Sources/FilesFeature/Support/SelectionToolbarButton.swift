import DesignSystem
import SwiftUI

/// One glyph button in a multi-select bottom toolbar. A single definition so the bars in
/// Browse, Downloads and Favorites share one icon size, tint, haptic and appear/disappear
/// transition, rather than each screen restyling the same button.
struct SelectionToolbarButton: View {
    let icon: Image
    var role: ButtonRole?
    var tint: Color?
    var accessibilityLabel: String?
    var isDisabled: Bool
    let action: () -> Void

    init(
        icon: Image,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        accessibilityLabel: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.role = role
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    private enum Constants {
        static let iconSize: CGFloat = .iconMedium
    }

    var body: some View {
        #if os(macOS)
            // The Mac toolbar sizes its own glyphs; a hand sized icon looked oversized there.
            Button(role: role, action: action) {
                icon
                    .foregroundStyle(tint ?? Color.primaryDS)
            }
            .disabled(isDisabled)
            .help(accessibilityLabel ?? "")
            .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        #else
            Button(role: role, action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundStyle(tint ?? Color.primaryDS)
            }
            .buttonStyle(DSHapticButtonStyle())
            .disabled(isDisabled)
            .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
            .transition(.scale.combined(with: .opacity))
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Where select mode actions sit: the bottom bar on iOS; centered in the toolbar on a Mac,
    /// which has no bottom bar.
    static var selectionBar: ToolbarItemPlacement {
        #if os(macOS)
            .principal
        #else
            .bottomBar
        #endif
    }
}

/// Applies `.accessibilityLabel` only when a label is provided, so a button that relies on its
/// glyph's own label (as Browse's bottom bar does) is left untouched.
private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}
