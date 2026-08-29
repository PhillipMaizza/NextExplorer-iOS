import SwiftUI

private enum Constants {
    static let cornerRadius: CGFloat = .radiusCard
    static let padding: CGFloat = .space16
    static let spacing: CGFloat = .space8
    static let iconSize: CGFloat = .iconSmall
    static let fillAlpha: Double = 0.12
}

/// A full-width inline error card: a leading warning icon and an error-styled message on a
/// red-tinted rounded background. Used wherever a screen surfaces a failed action without an
/// alert (form submits, panel loads).
public struct DSErrorCard: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Constants.spacing) {
            IconKit.warning
                .resizable().scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundStyle(Color.negative)
            Text(message)
                .type(.body3(.semibold), style: .error)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Constants.padding)
        .background(RoundedRectangle(cornerRadius: Constants.cornerRadius).fill(Color.negative.opacity(Constants.fillAlpha)))
    }
}

#Preview {
    DSErrorCard("Couldn't reach the server. Check your connection and try again.")
        .padding()
}
