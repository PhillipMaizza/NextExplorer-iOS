import DesignSystem
import SwiftUI

struct FavoriteGlyph: View {
    let icon: Image
    let tint: Color?
    let isFilled: Bool

    var body: some View {
        icon
            .resizable()
            .scaledToFit()
            .symbolVariant(isFilled ? .fill : .none)
            .foregroundStyle(tint ?? Color.accent)
            .frame(width: Constants.glyph, height: Constants.glyph)
            .frame(width: Constants.frame, height: Constants.frame)
    }
}

private enum Constants {
    static let glyph: CGFloat = .size20
    static let frame: CGFloat = .iconMedium
}

#Preview("Glyphs") {
    HStack(spacing: .space16) {
        FavoriteGlyph(icon: IconKit.home, tint: nil, isFilled: true)
        FavoriteGlyph(icon: IconKit.star, tint: Color.positive, isFilled: false)
        FavoriteGlyph(icon: IconKit.photo, tint: Color.negative, isFilled: true)
    }
    .padding(.space16)
}

#Preview("In favorite rows") {
    VStack(spacing: .space16) {
        FileRowView(name: "Plain folder", isDirectory: true)
        FileRowView(
            name: "Home",
            isDirectory: true,
            customIcon: IconKit.home,
            isCustomIconFilled: true
        )
        FileRowView(
            name: "Projects",
            isDirectory: true,
            customIcon: IconKit.star,
            customIconTint: Color.positive
        )
        FileRowView(
            name: "Photos",
            isDirectory: true,
            customIcon: IconKit.photo,
            customIconTint: Color.negative,
            isCustomIconFilled: true,
            isAvailableOffline: true
        )
    }
    .padding(.space16)
}
