#if os(macOS)
    import SwiftUI

    public struct MacKeyHint: View {
        private let text: String
        private let isHighlighted: Bool

        public init(_ text: String, isHighlighted: Bool = false) {
            self.text = text
            self.isHighlighted = isHighlighted
        }

        public var body: some View {
            Text(text)
                .type(.caption(.semibold))
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? Color.accentText : Color.macChromeSecondary)
                .padding(.horizontal, .space8)
                .padding(.vertical, .space2)
                .background(
                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        .fill(Color.macChromeButton)
                )
        }
    }

    #Preview("Key hints") {
        HStack(spacing: .space8) {
            MacKeyHint("\u{2318}1", isHighlighted: true)
            MacKeyHint("\u{2318}2")
            MacKeyHint("\u{2318},")
        }
        .padding()
        .background(Color.macChrome)
    }
#endif
