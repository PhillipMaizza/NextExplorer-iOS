#if os(macOS)
    import Localization
    import SwiftUI

    public struct MacIconButton: View {
        private enum Metrics {
            static let miniGlyph: CGFloat = 9
        }

        public enum Size {
            case regular
            case compact
            case mini

            var side: CGFloat {
                switch self {
                case .regular: MacControlHeight.large.points
                case .compact: MacControlHeight.regular.points
                case .mini: MacControlHeight.mini.points
                }
            }

            var glyph: CGFloat {
                switch self {
                case .regular: .iconSmall
                case .compact: .iconXSmall
                case .mini: Metrics.miniGlyph
                }
            }

            var weight: Font.Weight {
                self == .mini ? .bold : .regular
            }
        }

        let icon: Image
        let label: String
        let isFilled: Bool
        let size: Size
        let tint: Color
        let action: () -> Void

        public init(
            _ icon: Image,
            label: String,
            isFilled: Bool = true,
            size: Size = .regular,
            tint: Color = .primaryDS,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.label = label
            self.isFilled = isFilled
            self.size = size
            self.tint = tint
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .fontWeight(size.weight)
                    .macSquare(size.glyph)
                    .foregroundStyle(tint)
                    .macSquare(size.side)
                    .background(Circle().fill(isFilled ? Color.macSegment : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(label)
        }
    }

    #Preview("Icon buttons") {
        HStack(spacing: .space8) {
            MacIconButton(IconKit.ellipsis, label: L10n.Common.more) {}
            MacIconButton(IconKit.close, label: L10n.Common.close, isFilled: false) {}
            MacIconButton(IconKit.close, label: L10n.Common.close, size: .compact) {}
            MacIconButton(IconKit.retry, label: L10n.Common.retry, size: .mini, tint: .accentText) {}
            MacIconButton(IconKit.close, label: L10n.Common.close, size: .mini, tint: .secondaryDS) {}
        }
        .padding(.space16)
        .background(Color.macCard)
    }
#endif
