import DesignSystem
import SwiftUI

private enum Constants {
    static let size: CGFloat = .size40
    static let glyphSize: CGFloat = .size20
}

/// An audience without a face, a public link's globe or unnamed people, as a glyph in a hairline
/// circle the size of a person circle beside it.
struct SharedIconCircle: View {
    let icon: Image

    var body: some View {
        icon
            .resizable().scaledToFit()
            .foregroundStyle(Color.secondaryDS)
            .frame(width: Constants.glyphSize, height: Constants.glyphSize)
            .frame(width: Constants.size, height: Constants.size)
            .background(Circle().fill(Color.backgroundPrimary))
            .overlay(Circle().strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline))
            .accessibilityHidden(true)
    }
}

#Preview("Icon circle: globe") {
    SharedIconCircle(icon: IconKit.web)
        .padding()
        .background(Color.backgroundSecondary)
}

#Preview("Icon circle: people, dark") {
    SharedIconCircle(icon: IconKit.people)
        .padding()
        .background(Color.backgroundSecondary)
        .preferredColorScheme(.dark)
}
