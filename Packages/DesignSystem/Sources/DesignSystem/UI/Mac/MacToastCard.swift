#if os(macOS)
    import CoreModels
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 340
        static let glyphBaselineDrop: CGFloat = 5
        static let closeSize: CGFloat = 22
        static let closeGlyph: CGFloat = 9
    }

    struct MacToastCard: View {
        let message: DSToastMessage
        var collapsedHeight: CGFloat?
        let onAction: () -> Void
        let onClose: () -> Void
        var onHeight: (CGFloat) -> Void = { _ in }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
        }

        var body: some View {
            card
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
                .opacity(collapsedHeight == nil ? 1 : 0)
                .frame(width: Metrics.width)
                .frame(height: collapsedHeight, alignment: .top)
                .clipped()
                .background { surface }
                .accessibilityElement(children: .contain)
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
                closeButton
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.glyphBaselineDrop }
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, isSingleLine ? .space16 : .space12)
        }

        private var isSingleLine: Bool {
            message.detail == nil && message.actionTitle == nil
        }

        @ViewBuilder
        private var badge: some View {
            if let icon = message.icon {
                Text(icon)
                    .type(.body2(.semibold))
                    .foregroundStyle(message.tint)
            } else {
                DSSpinner(size: .small)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.glyphBaselineDrop }
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
        }
    }

    private struct MacToastCardPreview: View {
        let message: DSToastMessage

        var body: some View {
            MacToastCard(
                message: message,
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

    #Preview("Light") {
        MacToastCardPreview(message: .success("3 items moved to the trash", actionTitle: "Open Trash") {})
            .preferredColorScheme(.light)
    }
#endif
