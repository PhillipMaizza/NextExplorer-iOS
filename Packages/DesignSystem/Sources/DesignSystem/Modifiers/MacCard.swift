#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let shadowRadius: CGFloat = 1.5
        static let shadowOffset: CGFloat = 1
    }

    public extension View {
        func macCard() -> some View {
            background(
                RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                    .fill(Color.macCard)
                    .shadow(color: .macCardShadow, radius: Constants.shadowRadius, y: Constants.shadowOffset)
            )
            .clipShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        }

        func macChromeBackground() -> some View {
            background(Color.macChrome.ignoresSafeArea())
        }

        func macGroupedRows() -> some View {
            background(
                RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
                    .fill(Color.macRow)
            )
        }
    }

    #Preview("Card on chrome") {
        HStack(spacing: .space12) {
            Text(verbatim: "Documents")
                .type(.headline3)
                .frame(width: 320, height: 200, alignment: .topLeading)
                .padding(.space32)
                .macCard()
            VStack(alignment: .leading) {
                Text(verbatim: "Budget 2026.xlsx").type(.body2(.regular))
                Text(verbatim: "90 KB").type(.body3(.regular), style: .secondary)
            }
            .padding(.space16)
            .macGroupedRows()
        }
        .padding(.space24)
        .macChromeBackground()
    }
#endif
