import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconXSmall
    static let padding: CGFloat = .space8
}

extension View {
    /// Grows a small control's tappable area to the 44pt touch minimum without changing its layout
    /// size or how it draws: the hit region is padded out and the layout padding taken back. The Mac
    /// pointer has no such minimum, so it is a no op there.
    func dsMinimumHitTarget() -> some View {
        #if os(macOS)
            self
        #else
            modifier(DSMinimumHitTargetModifier())
        #endif
    }
}

#if os(iOS)
    private struct DSMinimumHitTargetModifier: ViewModifier {
        @State private var controlSize: CGSize = .zero

        func body(content: Content) -> some View {
            let expansion = DSHitTarget.expansion(for: controlSize)
            content
                .onGeometryChange(for: CGSize.self, of: \.size) { controlSize = $0 }
                .padding(.horizontal, expansion.width)
                .padding(.vertical, expansion.height)
                .contentShape(Rectangle())
                .padding(.horizontal, -expansion.width)
                .padding(.vertical, -expansion.height)
                .preference(key: DSHitTargetAppliedKey.self, value: true)
        }
    }

    /// Reports that a control went through `dsMinimumHitTarget`, so a test can tell a control that
    /// has the hit target from one that lost it (the modifier is otherwise invisible).
    struct DSHitTargetAppliedKey: PreferenceKey {
        static let defaultValue = false

        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = value || nextValue()
        }
    }
#endif

enum DSHitTarget {
    static let minimumSize: CGFloat = .size44
    /// The hit region grows evenly on the two opposite sides of an axis.
    private static let sidesPerAxis: CGFloat = 2

    /// How far the hit region must reach past each side of a control of `size` for it to be at least
    /// `minimumSize` wide and tall. Zero for a side that is already large enough.
    static func expansion(for size: CGSize) -> CGSize {
        CGSize(
            width: max(0, (minimumSize - size.width) / sidesPerAxis),
            height: max(0, (minimumSize - size.height) / sidesPerAxis)
        )
    }
}

/// The dismiss button every full-screen preview/cover uses: a plain `xmark` on a frosted
/// material chip, legible over any content behind it (photos, video, dark code editors)
/// without needing a theme-adaptive tint.
public struct DSCloseButton: View {
    private let action: () -> Void
    private let accessibilityLabel: String

    /// `accessibilityLabel` defaults to the English "Close"; localized call sites pass their
    /// own `L10n` string so this component stays free of an app copy dependency.
    public init(action: @escaping () -> Void, accessibilityLabel: String = "Close") {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Button(action: action) {
            IconKit.close
                .resizable()
                .foregroundStyle(Color.primaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .padding(Constants.padding)
                .dsGlass(interactive: true, in: Circle())
                .dsMinimumHitTarget()
        }
        .buttonStyle(DSHapticButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ZStack {
        Color.black
        DSCloseButton(action: {})
    }
}
