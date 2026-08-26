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

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconKit.xmark
                .resizable()
                .foregroundStyle(Color.primaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .padding(Constants.padding)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .accessibilityLabel("Close")
    }
}

#Preview {
    ZStack {
        Color.black
        DSCloseButton(action: {})
    }
}
