import SwiftUI

private struct RoundedFieldModifier: ViewModifier {
    var height: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, .space12)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline)
            )
    }
}

public extension View {
    /// The one field treatment for every text/secure field outside a native alert: a fixed
    /// `.radiusControl` corner, a hairline `borderPrimary` border, no fill, 48pt tall by
    /// default. Login's labelled `DSFieldContainer` is the deliberate exception.
    func roundedFieldStyle(height: CGFloat = .size48) -> some View {
        modifier(RoundedFieldModifier(height: height))
    }
}
