import SwiftUI

private enum Constants {
    static let cornerRadius: CGFloat = .radiusCard
    static let padding: CGFloat = .space16
    static let spacing: CGFloat = .space8
    static let iconSize: CGFloat = .iconSmall
    static let fillAlpha: Double = 0.12
}

/// A full-width inline notice: a leading `info` glyph and an attention-styled message on an
/// amber-tinted rounded background. The calmer sibling of `DSErrorCard` — for a heads-up the
/// user should read but that isn't a failure (an insecure connection, a caveat about a
/// setting).
public struct DSInfoCard: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Constants.spacing) {
            IconKit.info
                .resizable().scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundStyle(Color.attention)
            Text(message)
                .type(.body3(.semibold), style: .warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Constants.padding)
        .background(RoundedRectangle(cornerRadius: Constants.cornerRadius).fill(Color.attention.opacity(Constants.fillAlpha)))
    }
}

#Preview {
    VStack(spacing: .space16) {
        DSInfoCard("This connection isn't encrypted. Your password and session are sent in the clear over the local network.")
        DSInfoCard("Short note.")
    }
    .padding()
    .background(Color.backgroundPrimary)
}
