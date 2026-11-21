import DesignSystem
import Localization
import SwiftUI

/// The top of a sign in page past the first: a back chevron, and the page's title centered
/// when it has one.
struct LoginBackBar: View {
    let title: String?
    let onBack: () -> Void

    private enum Constants {
        static let height: CGFloat = .size44
        static let titleHorizontalPadding: CGFloat = .size44
        static let chevronSize: CGFloat = .iconSmall
        static let chevronWeight: Font.Weight = .semibold
    }

    var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .type(.body1(.semibold), style: .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Constants.titleHorizontalPadding)
            }

            HStack {
                Button(action: onBack) {
                    // Sized via font, not `.resizable()` into a square frame: a chevron is not
                    // square, so a square frame stretches the glyph. The 44pt frame is the tap target.
                    IconKit.back
                        .font(.system(size: Constants.chevronSize, weight: Constants.chevronWeight))
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: .size44, height: .size44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabel(L10n.Common.back)
                Spacer()
            }
        }
        .frame(height: Constants.height)
        .padding(.horizontal, .space16)
        .padding(.top, .space16)
    }
}

#Preview("With title") {
    LoginBackBar(title: "nextexplorer.example.com", onBack: {})
}

#Preview("Back only") {
    LoginBackBar(title: nil, onBack: {})
}
