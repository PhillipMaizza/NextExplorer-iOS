#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let washOpacity: Double = 0.25
        static let pillWashOpacity: Double = .opacityWash
    }

    public struct MacChip: View {
        public enum Kind: Sendable {
            case tag
            case pill
        }

        public enum Size: Sendable {
            case regular
            case small

            var textType: Typography.TextType {
                switch self {
                case .regular: .body3(.semibold)
                case .small: .caption(.semibold)
                }
            }

            var verticalPadding: CGFloat {
                switch self {
                case .regular: .space4
                case .small: .space2
                }
            }

            var minHeight: CGFloat {
                switch self {
                case .regular: .size24
                case .small: .zero
                }
            }

            var horizontalPadding: CGFloat {
                switch self {
                case .regular: .space8
                case .small: .space8
                }
            }
        }

        public enum Tone: Sendable {
            case green
            case red
            case gray
            case amber

            var text: Color {
                switch self {
                case .green: .macTagGreen
                case .red: .macTagRed
                case .gray: .macTagGray
                case .amber: .macTagAmber
                }
            }

            var fill: Color {
                switch self {
                case .green: .macTagGreenFill
                case .red: .macTagRedFill
                case .gray: .macTagGrayFill
                case .amber: .macTagAmberFill
                }
            }
        }

        private let text: String
        private let tint: Color
        private let style: Typography.TextStyle
        private let kind: Kind
        private var tone: Tone?
        private var size: Size = .regular
        private var icon: Image?

        public init(
            text: String,
            tint: Color = .tertiaryDS,
            style: Typography.TextStyle = .tertiary,
            kind: Kind = .tag
        ) {
            self.text = text
            self.tint = tint
            self.style = style
            self.kind = kind
        }

        private var pill: some View {
            HStack(spacing: .space4) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .macSquare(.iconXSmall)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .type(size.textType)
                    .lineLimit(1)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .macMinHeight(points: size.minHeight)
        }

        public init(text: String, tone: Tone, size: Size = .regular, icon: Image? = nil) {
            self.init(text: text, kind: .pill)
            self.tone = tone
            self.size = size
            self.icon = icon
        }

        public var body: some View {
            switch kind {
            case .tag:
                Text(text)
                    .type(.caption(.regular), style: style)
                    .padding(.horizontal, .space4)
                    .padding(.vertical, .space2)
                    .background(
                        RoundedRectangle(cornerRadius: .radiusXSmall, style: .continuous)
                            .fill(tint.opacity(Constants.washOpacity))
                    )
                    .accessibilityHidden(true)
            case .pill:
                if let tone {
                    pill.foregroundStyle(tone.text)
                        .background(Capsule().fill(tone.fill))
                } else {
                    pill.foregroundStyle(style.color)
                        .background(Capsule().fill(tint.opacity(Constants.pillWashOpacity)))
                }
            }
        }
    }

    public extension MacChip {
        static func admin(size: Size = .small) -> MacChip {
            MacChip(
                text: L10n.UserManagement.badgeAdmin,
                tone: .amber,
                size: size,
                icon: IconKit.macShield
            )
        }
    }

    public struct MacAdminMark: View {
        public init() {}

        public var body: some View {
            IconKit.macShield
                .resizable()
                .scaledToFit()
                .macSquare(.iconXSmall)
                .foregroundStyle(Color.macTagAmber)
                .help(L10n.UserManagement.badgeAdmin)
                .accessibilityLabel(L10n.UserManagement.badgeAdmin)
        }
    }

    public struct MacIconChip: View {
        private typealias Size = MacChip.Size
        private let icon: Image
        private let tone: MacChip.Tone
        private let help: String

        public init(icon: Image, tone: MacChip.Tone, help: String) {
            self.icon = icon
            self.tone = tone
            self.help = help
        }

        public var body: some View {
            icon
                .resizable()
                .scaledToFit()
                .macSquare(MacActionMenuMetrics.iconSize)
                .foregroundStyle(tone.text)
                .macSquare(Size.regular.minHeight)
                .background(Circle().fill(tone.fill))
                .contentShape(Circle())
                .help(help)
                .accessibilityElement()
                .accessibilityLabel(help)
                .accessibilityAddTraits(.isImage)
        }
    }

    #Preview("Tones") {
        HStack {
            MacChip(text: L10n.ActivityLog.outcomeOk, tone: .green)
            MacChip(text: L10n.ActivityLog.outcomeRefused, tone: .red)
            MacChip(text: L10n.ServerTools.notUsed, tone: .gray)
            MacChip(text: L10n.ServerTools.notUsed, tone: .amber, size: .small)
            MacChip.admin()
            MacAdminMark()
            MacChip(text: L10n.UserManagement.badgeAdmin, tone: .amber)
            MacChip(text: L10n.Shared.anyoneWithLink, tone: .gray, icon: IconKit.web)
        }
        .padding()
    }

    #Preview("Tags") {
        HStack {
            MacChip(text: "\u{2318} 4")
            MacChip(text: "1.2.0", tint: .accent, style: .link)
        }
        .padding()
    }

    #Preview("Pills") {
        HStack {
            MacChip(text: L10n.Common.on, tint: .positive, style: .success, kind: .pill)
            MacChip(text: L10n.Common.off, kind: .pill)
            MacChip(text: L10n.Common.never, tint: .accent, style: .link, kind: .pill)
            MacChip(text: L10n.Common.remove, tint: .negative, style: .error, kind: .pill)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
