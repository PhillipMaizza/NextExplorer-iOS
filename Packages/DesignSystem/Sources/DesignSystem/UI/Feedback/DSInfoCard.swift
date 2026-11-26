import SwiftUI

/// A full width inline notice: a leading `info` glyph and an attention styled message on an
/// amber tinted rounded background. The calmer sibling of `DSErrorCard`: for a heads up the
/// user should read but that isn't a failure (an insecure connection, a caveat about a
/// setting).
public struct DSInfoCard: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        DSNoticeCard(icon: IconKit.info, tint: .attention, style: .warning, message: message)
    }
}

#Preview {
    VStack(spacing: .space16) {
        DSInfoCard(
            "This connection isn't encrypted. Your password and session are sent in the clear over the local network."
        )
        DSInfoCard("Short note.")
    }
    .padding()
    .background(Color.backgroundPrimary)
}
