import SwiftUI

private struct RoundedFieldModifier: ViewModifier {
    var height: CGFloat
    var isFocused: Bool

    private var borderStyle: AnyShapeStyle {
        isFocused ? AnyShapeStyle(LinearGradient.accent) : AnyShapeStyle(Color.borderPrimary)
    }

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, .space12)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusLarge)
                    .strokeBorder(borderStyle, lineWidth: isFocused ? .borderWidthFocused : .borderWidthHairline)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

public extension View {
    /// The one field treatment for every text/secure field outside a native alert: a fixed
    /// `.radiusControl` corner, a hairline `borderPrimary` border, no fill, 48pt tall by
    /// default. Pass `isFocused` to light the border with the accent gradient while the field
    /// is first responder. Login's labelled `DSFieldContainer` is the deliberate exception.
    func roundedFieldStyle(height: CGFloat = .size48, isFocused: Bool = false) -> some View {
        modifier(RoundedFieldModifier(height: height, isFocused: isFocused))
    }
}
