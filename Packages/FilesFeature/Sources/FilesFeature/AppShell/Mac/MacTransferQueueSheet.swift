#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listHeight: CGFloat = 300
        static let listMaxHeight: CGFloat = 420
        static let tileSize: CGFloat = .size32
        static let badgeGlyph: CGFloat = .size16
        static let clearGlyph: CGFloat = .size20
        static let clearHitSize: CGFloat = 22
    }

    struct MacTransferQueueSheet: View {
        let icon: Image
        let title: String
        let summary: String
        let progress: Double?
        let rows: [TransferQueueRow]
        let emptyMessage: String
        let canClear: Bool
        let canRetryFailed: Bool
        let onCancel: (UUID) -> Void
        let onRetry: (UUID) -> Void
        let onUploadMore: (() -> Void)?
        let onRetryFailed: () -> Void
        let onClear: () -> Void
        let onClose: () -> Void

        @State private var contentHeight: CGFloat = .zero

        var body: some View {
            VStack(alignment: .leading, spacing: .space24) {
                header
                list
                footer
            }
            .padding(.space24)
            .frame(width: MacFormSheetMetrics.width)
            .background(Color.macField)
            .onExitCommand(perform: onClose)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: .space12) {
                HStack(alignment: .center, spacing: .space12) {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.badgeGlyph, height: Metrics.badgeGlyph)
                        .foregroundStyle(Color.accentText)
                        .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                        .background(Circle().fill(Color.accent.opacity(.opacityWash)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(title).type(.headline4)
                        if !rows.isEmpty {
                            Text(summary)
                                .type(.body3(.regular), style: .secondary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: .zero)
                    MacIconButton(IconKit.close, label: L10n.Common.close, size: .compact, action: onClose)
                }
                if let progress {
                    MacProgressBar(value: progress)
                }
            }
        }

        @ViewBuilder
        private var list: some View {
            if rows.isEmpty {
                Text(emptyMessage)
                    .type(.body2(.regular), style: .secondary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.listHeight)
            } else {
                ScrollView {
                    VStack(spacing: .zero) {
                        ForEach(rows) { row in
                            rowView(row)
                                .overlay(alignment: .top) {
                                    if row.id != rows.first?.id {
                                        Divider().overlay(Color.macLine)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, .space12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = max(contentHeight, $0)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, Metrics.listMaxHeight))
                .background(Color.macChromeButton, in: listShape)
                .overlay(listShape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
            }
        }

        private var listShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
        }

        private var footer: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: .space8) {
                    leadingButtons
                    Spacer(minLength: .space8)
                    trailingButtons
                }
                VStack(alignment: .trailing, spacing: .space8) {
                    HStack(spacing: .space8) {
                        leadingButtons
                        Spacer(minLength: .zero)
                    }
                    HStack(spacing: .space8) { trailingButtons }
                }
            }
        }

        @ViewBuilder
        private var leadingButtons: some View {
            if let onUploadMore {
                Button(action: onUploadMore) {
                    HStack(spacing: .space4) {
                        IconKit.upload
                        Text(L10n.Uploads.uploadMore)
                    }
                }
                .buttonStyle(.macDS(.primary))
                .fixedSize()
            }
            if canRetryFailed {
                Button(L10n.Common.retryFailed, action: onRetryFailed)
                    .buttonStyle(.macDS(.secondary))
                    .fixedSize()
            }
        }

        @ViewBuilder
        private var trailingButtons: some View {
            Button(L10n.Common.clearFinished, action: onClear)
                .buttonStyle(.macDS(.secondary))
                .disabled(!canClear)
                .fixedSize()
            Button(L10n.Common.done, action: onClose)
                .buttonStyle(.macDS(.secondary))
                .keyboardShortcut(.defaultAction)
                .fixedSize()
        }

        private func rowView(_ row: TransferQueueRow) -> some View {
            HStack(spacing: .space12) {
                FileTypeIcon(kind: (row.name as NSString).pathExtension.lowercased())
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                VStack(alignment: .leading, spacing: .space4) {
                    HStack(spacing: .space4) {
                        Text(row.name)
                            .type(.body2(.semibold))
                            .foregroundStyle(isWaiting(row) ? Color.secondaryDS : Color.primaryDS)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if case .done = row.status {
                            Text(IconKit.checkmarkCircleFill)
                                .type(.body3(.regular))
                                .foregroundStyle(Color.positiveText)
                                .accessibilityLabel(L10n.Common.done)
                        }
                    }
                    switch row.status {
                    case let .running(progress, _):
                        MacProgressBar(value: progress)
                            .padding(.top, .space2)
                    case let .failed(message):
                        Text(message)
                            .type(.body3(.regular), style: .error)
                            .lineLimit(2)
                            .help(message)
                    case .waiting, .done:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingButton(row)
            }
            .padding(.vertical, .space12)
        }

        private func isWaiting(_ row: TransferQueueRow) -> Bool {
            if case .waiting = row.status {
                true
            } else {
                false
            }
        }

        @ViewBuilder
        private func trailingButton(_ row: TransferQueueRow) -> some View {
            switch row.status {
            case .waiting, .running:
                MacIconButton(IconKit.close, label: L10n.Common.cancel, size: .mini, tint: .secondaryDS) {
                    onCancel(row.id)
                }
            case .done:
                Button { onCancel(row.id) } label: {
                    IconKit.closeCircle
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.bold)
                        .frame(width: Metrics.clearGlyph, height: Metrics.clearGlyph)
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Metrics.clearHitSize, height: Metrics.clearHitSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabelWithTooltip(L10n.Common.clear)
            case .failed:
                MacIconButton(IconKit.retry, label: L10n.Common.retry, size: .mini, tint: .accentText) {
                    onRetry(row.id)
                }
            }
        }
    }

    @MainActor
    private func queuePreview(_ rows: [TransferQueueRow]) -> some View {
        MacTransferQueueSheet(
            icon: IconKit.uploadFill,
            title: "Uploads",
            summary: "1 of 4 uploaded · 1 upload failed · 40s left",
            progress: rows.isEmpty ? nil : 0.4,
            rows: rows,
            emptyMessage: "No uploads",
            canClear: !rows.isEmpty,
            canRetryFailed: !rows.isEmpty,
            onCancel: { _ in },
            onRetry: { _ in },
            onUploadMore: {},
            onRetryFailed: {},
            onClear: {},
            onClose: {}
        )
    }

    #Preview("Queue") {
        queuePreview([
            TransferQueueRow(id: UUID(), name: "notes.txt", status: .done("Projects")),
            TransferQueueRow(id: UUID(), name: "beach.jpg", status: .running(progress: 0.42, detail: nil)),
            TransferQueueRow(id: UUID(), name: "itinerary.pdf", status: .waiting),
            TransferQueueRow(id: UUID(), name: "movie.mkv", status: .failed("The connection was lost.")),
        ])
    }

    #Preview("Empty") {
        queuePreview([])
    }

    #Preview("Light") {
        queuePreview([
            TransferQueueRow(id: UUID(), name: "budget.xlsx", status: .done("Projects")),
            TransferQueueRow(
                id: UUID(),
                name: "logo-final.png",
                status: .running(progress: 0.65, detail: nil)
            ),
        ])
        .preferredColorScheme(.light)
    }
#endif
