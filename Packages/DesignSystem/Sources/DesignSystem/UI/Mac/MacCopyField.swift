#if os(macOS)
    import Localization
    import SwiftUI

    private enum Metrics {
        static let copySize: CGFloat = .size24
        static let shape = RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
    }

    public struct MacCopyField: View {
        private let text: AttributedString
        private let copyLabel: String
        private let onCopy: () -> Void

        public init(_ text: AttributedString, copyLabel: String, onCopy: @escaping () -> Void) {
            self.text = text
            self.copyLabel = copyLabel
            self.onCopy = onCopy
        }

        public init(_ text: String, copyLabel: String, onCopy: @escaping () -> Void) {
            self.init(AttributedString(text), copyLabel: copyLabel, onCopy: onCopy)
        }

        public var body: some View {
            HStack(alignment: .center, spacing: .space8) {
                Text(text)
                    .type(.body3(.regular))
                    .monospaced()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCopy) {
                    IconKit.macCopy
                        .resizable()
                        .scaledToFit()
                        .macSquare(.iconSmall)
                        .foregroundStyle(Color.primaryDS)
                        .macSquare(Metrics.copySize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabelWithTooltip(copyLabel)
            }
            .padding(.leading, .space12)
            .padding(.trailing, .space8)
            .padding(.vertical, .space12)
            .background(Metrics.shape.fill(Color.macField))
            .overlay(Metrics.shape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
        }
    }

    #Preview("Copy field") {
        VStack(spacing: .space16) {
            MacCopyField("https://cloud.example.com/share/k29fa", copyLabel: L10n.Common.copy) {}
            MacCopyField("JBSWY3DPEHPK3PXP", copyLabel: L10n.Common.copy) {}
        }
        .padding(.space24)
        .previewCanvasWidth(.control)
        .macCard()
    }
#endif
