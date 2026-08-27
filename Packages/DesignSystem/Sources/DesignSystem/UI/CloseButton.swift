import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconXSmall
    static let padding: CGFloat = .space8
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
