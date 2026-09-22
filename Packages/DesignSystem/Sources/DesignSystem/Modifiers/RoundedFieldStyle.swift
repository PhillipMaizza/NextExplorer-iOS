import SwiftUI

private struct RoundedFieldModifier: ViewModifier {
    var height: CGFloat
    var isFocused: Bool
    var bordered: Bool
    var cornerRadius: CGFloat

    private var borderStyle: AnyShapeStyle {
        isFocused ? AnyShapeStyle(Color.accent) : AnyShapeStyle(Color.borderPrimary)
    }

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, .space12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.backgroundSecondary)
            )
            .overlay {
                // Search fields sit on the gray page, where the white fill alone separates them,
                // so they opt out of the border entirely (matches the system search field).
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderStyle, lineWidth: isFocused ? .borderWidthFocused : .borderWidthHairline)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

public extension View {
    /// The one field treatment for every text/secure field outside a native alert: a fixed
    /// `.radiusControl` corner, a white `backgroundSecondary` fill, a hairline `borderPrimary`
    /// border, 48pt tall by default. Pass `isFocused` to light the border with the accent while
    /// the field is first responder. Pass `bordered: false` for a search field on the gray page,
    /// where the fill alone separates it and no border reads more like the system search field.
    /// Login's labelled `DSFieldContainer` is the deliberate exception. Pass `cornerRadius` to
    /// override the default `.radiusControl` (search fields pass `.radiusSearchField`).
    func roundedFieldStyle(
        height: CGFloat = .size48,
        isFocused: Bool = false,
        bordered: Bool = true,
        cornerRadius: CGFloat = .radiusControl
    ) -> some View {
        modifier(RoundedFieldModifier(height: height, isFocused: isFocused, bordered: bordered, cornerRadius: cornerRadius))
    }
}
