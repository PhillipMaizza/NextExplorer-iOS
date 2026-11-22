#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let washOpacity: Double = 0.14
        static let iconSize: CGFloat = .iconSmall
    }

    public struct MacNote: View {
        public enum Kind: Sendable {
            case error
            case warning
            case info
        }

        private let text: String
        private let kind: Kind

        public init(_ text: String, kind: Kind) {
            self.text = text
            self.kind = kind
        }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: .space8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - .space2 }
                    .accessibilityHidden(true)
                Text(text)
                    .type(.body3(.regular), style: textStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(tint)
            .padding(.space12)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .fill(fill)
            )
            .accessibilityElement(children: .combine)
        }

        private var icon: Image {
            switch kind {
            case .error: IconKit.error
            case .warning: IconKit.warning
            case .info: IconKit.info
            }
        }

        private var tint: Color {
            switch kind {
            case .error: .negativeText
            case .warning: .accentText
            case .info: .macChromeSecondary
            }
        }

        private var textStyle: Typography.TextStyle {
            switch kind {
            case .error: .error
            case .warning: .link
            case .info: .secondary
            }
        }

        private var fill: Color {
            switch kind {
            case .error: .negative.opacity(Constants.washOpacity)
            case .warning: .accent.opacity(Constants.washOpacity)
            case .info: .macRow
            }
        }
    }

    #Preview("Notes") {
        VStack(spacing: .space12) {
            MacNote("Could not reach that server. Check the address and try again.", kind: .error)
            MacNote("This connection isn't encrypted. Your password is sent in the clear.", kind: .warning)
            MacNote("Add a port (e.g. :3000).", kind: .info)
        }
        .padding(.space24)
        .frame(width: MacFormSheetMetrics.width)
        .macCard()
    }
#endif
