import SwiftUI

private struct RoundedFieldModifier: ViewModifier {
    var height: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, .space12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .stroke(Color.borderPrimary, lineWidth: .borderWidthHairline)
            )
    }
}

public extension View {
    /// A 40pt-tall, rounded-corner field treatment shared by every text/secure field.
    func roundedFieldStyle(height: CGFloat = .size40) -> some View {
        modifier(RoundedFieldModifier(height: height))
    }
}
