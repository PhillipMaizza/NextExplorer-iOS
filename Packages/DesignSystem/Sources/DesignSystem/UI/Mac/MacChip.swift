#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let washOpacity: Double = 0.25
        static let pillWashOpacity: Double = 0.16
    }

    public struct MacChip: View {
        public enum Kind: Sendable {
            case tag
            case pill
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
            Text(text)
                .font(Typography.TextType.body3(.semibold).font())
                .lineLimit(1)
                .padding(.horizontal, .space8)
                .padding(.vertical, .space2)
        }

        public init(text: String, tone: Tone) {
            self.init(text: text, kind: .pill)
            self.tone = tone
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

    #Preview("Tones") {
        HStack {
            MacChip(text: L10n.ActivityLog.outcomeOk, tone: .green)
            MacChip(text: L10n.ActivityLog.outcomeRefused, tone: .red)
            MacChip(text: L10n.ServerTools.notUsed, tone: .gray)
            MacChip(text: L10n.UserManagement.badgeAdmin, tone: .amber)
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
