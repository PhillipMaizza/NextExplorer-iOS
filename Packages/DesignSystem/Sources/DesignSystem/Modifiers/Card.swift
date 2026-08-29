import SwiftUI

/// Wraps content as a card: uniform padding on a `backgroundSecondary` fill rounded to
/// `.radiusCard`, stretched full width and leading aligned. The shape sheets already use to
/// group a form section or a summary block (`UploadReviewView`'s path/size block is the
/// reference); use this instead of re-inlining the background each time.
public struct DSCardModifier: ViewModifier {
    private let padding: CGFloat

    public init(padding: CGFloat) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard))
    }
}

public extension View {
    func dsCard(padding: CGFloat = .space16) -> some View {
        modifier(DSCardModifier(padding: padding))
    }
}

#Preview {
    VStack(spacing: .space16) {
        Text("A card").type(.body2(.regular), style: .primary(for: .label)).dsCard()
        VStack(alignment: .leading, spacing: .space8) {
            Text("Title").type(.body2(.bold), style: .primary(for: .label))
            Text("Detail line").type(.body3(.regular), style: .secondary)
        }
        .dsCard()
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
