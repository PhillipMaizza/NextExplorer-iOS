#if os(macOS)
    import CoreModels
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 340
        static let spinnerBaselineDrop: CGFloat = 5
        static let closeSize: CGFloat = 22
        static let closeGlyph: CGFloat = 9
        static let maxPlates = 2
        static let plateInset: CGFloat = .space8
        static let plateLift: CGFloat = .size6
    }

    struct MacToastCard: View {
        let message: DSToastMessage
        let waitingCount: Int
        let onAction: () -> Void
        let onClose: () -> Void

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
        }

        private var plates: [Int] {
            Array(stride(from: min(waitingCount, Metrics.maxPlates), to: 0, by: -1))
        }

        var body: some View {
            card
                .background(alignment: .top) {
                    ZStack {
                        ForEach(plates, id: \.self) { plate in
                            surface
                                .padding(.horizontal, Metrics.plateInset * CGFloat(plate))
                                .offset(y: -Metrics.plateLift * CGFloat(plate))
                        }
                    }
                }
                .frame(width: Metrics.width)
        }

        private var surface: some View {
            shape
                .fill(Color.macCard)
                .overlay { shape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline) }
                .elevation(.level4)
        }

        private var card: some View {
            HStack(alignment: .firstTextBaseline, spacing: .space8) {
                badge
                VStack(alignment: .leading, spacing: .space2) {
                    Text(message.text)
                        .type(.body2(.semibold))
                        .foregroundStyle(Color.primaryDS)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Toast.message)
                    if let detail = message.detail {
                        Text(detail)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.secondaryDS)
                    }
                    if let actionTitle = message.actionTitle, message.action != nil {
                        Button(actionTitle, action: onAction)
                            .buttonStyle(.macDS(.primary, size: .small))
                            .padding(.top, .space8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Metrics.closeSize)
            }
            .padding(.space12)
            .background { surface }
            .overlay(alignment: .topTrailing) { closeButton }
        }

        @ViewBuilder
        private var badge: some View {
            if let icon = message.icon {
                Text(icon)
                    .type(.body2(.semibold))
                    .foregroundStyle(message.tint)
            } else {
                DSSpinner(size: .small)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.spinnerBaselineDrop }
            }
        }

        private var closeButton: some View {
            Button(action: onClose) {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: Metrics.closeGlyph, height: Metrics.closeGlyph)
                    .frame(width: Metrics.closeSize, height: Metrics.closeSize)
                    .background(Circle().fill(Color.macSegment))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryDS)
            .accessibilityLabel(L10n.Common.close)
            .accessibilityIdentifier(AccessibilityIdentifiers.Toast.close)
            .padding(.space8)
        }
    }

    private struct MacToastCardPreview: View {
        let message: DSToastMessage
        var waitingCount = 0

        var body: some View {
            MacToastCard(
                message: message,
                waitingCount: waitingCount,
                onAction: {},
                onClose: {}
            )
            .padding(.space40)
            .background(Color.macChrome)
        }
    }

    #Preview("Success") {
        MacToastCardPreview(message: .success("Saved to Documents"))
    }

    #Preview("Success with detail and action") {
        MacToastCardPreview(message: .success(
            "Saved to Downloads",
            detail: "report.pdf",
            actionTitle: "Show in Finder"
        ) {})
    }

    #Preview("Failure with action") {
        MacToastCardPreview(message: .failure("Couldn't move 2 items", actionTitle: "Retry") {})
    }

    #Preview("Warning") {
        MacToastCardPreview(message: DSToastMessage(icon: IconKit.errorFill, text: "Unsupported file type"))
    }

    #Preview("Progress") {
        MacToastCardPreview(message: .progress("Compressing…"))
    }

    #Preview("Stacked, dark") {
        MacToastCardPreview(
            message: .success("3 items moved to the trash", actionTitle: "Open Trash") {},
            waitingCount: 2
        )
        .preferredColorScheme(.dark)
    }

    #Preview("Stacked, light") {
        MacToastCardPreview(
            message: .success("3 items moved to the trash", actionTitle: "Open Trash") {},
            waitingCount: 1
        )
        .preferredColorScheme(.light)
    }
#endif
