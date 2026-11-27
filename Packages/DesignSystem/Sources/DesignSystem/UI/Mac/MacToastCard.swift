#if os(macOS)
    import CoreModels
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 360
        static let glyphBaselineDrop: CGFloat = 5
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
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Toast.message)
                    if let detail = message.detail {
                        Text(detail)
                            .type(.body3(.regular))
                            .foregroundStyle(Color.secondaryDS)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let transfer = message.transfer {
                        MacTransferStatus(
                            fileName: transfer.fileName,
                            timeLeft: transfer.timeLeft,
                            fraction: transfer.fraction,
                            tint: transfer.hasFailures ? .accent : .positive
                        )
                        .padding(.top, .space8)
                    }
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                closeButton
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.glyphBaselineDrop }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space16)
        }

        @ViewBuilder
        private var actions: some View {
            if let actionTitle = message.actionTitle, message.action != nil {
                HStack(spacing: .space8) {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.macDS(.primary, size: .small))
                    if let transfer = message.transfer {
                        Spacer(minLength: .zero)
                        Button(transfer.cancelTitle, action: transfer.cancel)
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                }
                .padding(.top, .space16)
            }
        }

        @ViewBuilder
        private var badge: some View {
            if let icon = message.icon {
                Text(icon)
                    .type(.body2(.semibold))
                    .foregroundStyle(message.tint)
                    .accessibilityHidden(true)
            } else {
                DSSpinner(size: .small)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.glyphBaselineDrop }
            }
        }

        private var closeButton: some View {
            MacIconButton(IconKit.close, label: L10n.Common.close, size: .mini, tint: .secondaryDS, action: onClose)
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

    #Preview("Transfer") {
        MacToastCardPreview(message: .transfer(
            "Uploading 4 files",
            id: "uploads",
            icon: IconKit.uploadFill,
            fraction: 0.45,
            fileName: "brief-v2.pdf",
            timeLeft: "12s left",
            actionTitle: "Show All",
            action: {},
            cancelTitle: "Cancel all uploads",
            cancel: {}
        ))
    }

    #Preview("Light") {
        MacToastCardPreview(message: .success("3 items moved to the trash", actionTitle: "Open Trash") {})
            .preferredColorScheme(.light)
    }
#endif
