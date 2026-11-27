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
                MacIconGlyph(icon, isFilled: isFilled, size: size, tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(label)
        }
    }

    public struct MacIconGlyph: View {
        let icon: Image
        let isFilled: Bool
        let size: MacIconButton.Size
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        public init(
            _ icon: Image,
            isFilled: Bool = true,
            size: MacIconButton.Size = .regular,
            tint: Color = .primaryDS
        ) {
            self.icon = icon
            self.isFilled = isFilled
            self.size = size
            self.tint = tint
        }

        public var body: some View {
            icon
                .resizable()
                .scaledToFit()
                .fontWeight(size.weight)
                .macSquare(size.glyph)
                .foregroundStyle(isEnabled ? tint : Color.macChromeDisabled)
                .macSquare(size.side)
                .background {
                    if isFilled {
                        Circle().fill(Color.macButtonRaised)
                            .elevation(.level1)
                    }
                }
                .contentShape(Circle())
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
