#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacTransferQueueMetrics {
        static let width: CGFloat = 640
    }

    private enum Metrics {
        static let listHeight: CGFloat = 300
        static let listMaxHeight: CGFloat = 420
        static let headerTile: CGFloat = .size40
        static let tileSize: CGFloat = .size32
        static let rowGlyph: CGFloat = .size20
        static let rowHitSize: CGFloat = 22
    }

    struct MacTransferQueueSheet: View {
        let icon: Image
        let title: String
        let summary: TransferQueueSummary
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
        let onMinimize: (() -> Void)?
        let onClose: () -> Void

        @State private var contentHeight: CGFloat = .zero
        @FocusState private var isFocused: Bool

        private var progressTint: Color {
            summary.failure == nil ? .positive : .accent
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space24) {
                header
                list
                footer
            }
            .padding(.space24)
            .frame(width: MacTransferQueueMetrics.width)
            .background(Color.macField, in: panelShape)
            .clipShape(panelShape)
            .overlay(panelShape.strokeBorder(Color.macLine))
            .shadow(
                color: .black.opacity(MacPeekMetrics.shadowOpacity),
                radius: MacPeekMetrics.shadowRadius,
                y: MacPeekMetrics.shadowOffset
            )
            .background {
                Color.clear
                    .focusable()
                    .focused($isFocused)
                    .focusEffectDisabled()
            }
            .onAppear { isFocused = true }
            .onExitCommand(perform: onMinimize ?? onClose)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(title)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: .space12) {
                HStack(alignment: .center, spacing: .space12) {
                    MacEmptyGuideTile(icon: icon, size: Metrics.headerTile)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(title).type(.headline4)
                        if !rows.isEmpty {
                            summaryLine
                        }
                    }
                    Spacer(minLength: .zero)
                    if let onMinimize {
                        MacIconButton(IconKit.minimize, label: L10n.Common.minimize, size: .compact, action: onMinimize)
                    } else {
                        MacIconButton(IconKit.close, label: L10n.Common.close, size: .compact, action: onClose)
                    }
                }
                if let progress {
                    MacProgressBar(value: progress, tint: progressTint)
                }
            }
        }

        private var summaryLine: some View {
            HStack(alignment: .firstTextBaseline, spacing: .zero) {
                Text(summary.done)
                    .type(.body3(.regular), style: .secondary)
                if let failure = summary.failure {
                    if !summary.done.isEmpty {
                        Text(DownloadProgressText.separator)
                            .type(.body3(.regular), style: .secondary)
                    }
                    Text(failure)
                        .type(.body3(.semibold), style: .error)
                }
                if let timeLeft = summary.timeLeft {
                    Text(DownloadProgressText.separator + timeLeft)
                        .type(.body3(.regular), style: .secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
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

        private var panelShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MacPeekMetrics.radius, style: .continuous)
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
            Button(L10n.Common.done, action: onMinimize ?? onClose)
                .buttonStyle(.macDS(.secondary))
                .keyboardShortcut(.defaultAction)
                .fixedSize()
        }

        private func rowView(_ row: TransferQueueRow) -> some View {
            HStack(spacing: .space12) {
                FileTypeIcon(kind: (row.name as NSString).pathExtension.lowercased())
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                VStack(alignment: .leading, spacing: .space4) {
                    HStack(alignment: .firstTextBaseline, spacing: .space16) {
                        HStack(alignment: .firstTextBaseline, spacing: .space4) {
                            Text(row.name)
                                .type(.body2(.semibold))
                                .foregroundStyle(isWaiting(row) ? Color.secondaryDS : Color.primaryDS)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            statusBadge(row.status)
                        }
                        if case let .running(progress, detail) = row.status {
                            Spacer(minLength: .zero)
                            MacTransferProgressLabel(timeLeft: detail, fraction: progress)
                        }
                    }
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .type(.body3(.regular), style: .secondary)
                            .monospacedDigit()
                    }
                    switch row.status {
                    case let .running(progress, _):
                        MacProgressBar(value: progress, tint: progressTint)
                            .padding(.top, .space4)
                    case let .failed(message):
                        Text(message)
                            .type(.body3(.semibold), style: .error)
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.name)
        }

        @ViewBuilder
        private func statusBadge(_ status: TransferQueueRow.Status) -> some View {
            switch status {
            case .done:
                Text(IconKit.checkmarkCircleFill)
                    .type(.body3(.regular))
                    .foregroundStyle(Color.positiveText)
                    .accessibilityLabel(L10n.Common.done)
            case .failed:
                Text(IconKit.errorFill)
                    .type(.body3(.regular))
                    .foregroundStyle(Color.negativeText)
                    .accessibilityHidden(true)
            case .waiting, .running:
                EmptyView()
            }
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
                rowCircleButton(IconKit.closeCircle, tint: .secondaryDS, label: L10n.Common.clear) {
                    onCancel(row.id)
                }
            case .failed:
                HStack(spacing: .space4) {
                    rowCircleButton(IconKit.retryCircleFill, tint: .accentText, label: L10n.Common.retry) {
                        onRetry(row.id)
                    }
                    rowCircleButton(IconKit.closeCircle, tint: .secondaryDS, label: L10n.Common.clear) {
                        onCancel(row.id)
                    }
                }
            }
        }

        private func rowCircleButton(
            _ icon: Image,
            tint: Color,
            label: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: Metrics.rowGlyph, height: Metrics.rowGlyph)
                    .foregroundStyle(tint)
                    .frame(width: Metrics.rowHitSize, height: Metrics.rowHitSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(label)
        }
    }

    @MainActor
    private func queuePreview(_ rows: [TransferQueueRow], failure: String? = "1 upload failed") -> some View {
        MacTransferQueueSheet(
            icon: IconKit.macUpload,
            title: "Uploads",
            summary: TransferQueueSummary(done: "1 of 4 uploaded", failure: failure, timeLeft: "40s left"),
            progress: rows.isEmpty ? nil : 0.4,
            rows: rows,
            emptyMessage: "No uploads",
            canClear: !rows.isEmpty,
            canRetryFailed: failure != nil,
            onCancel: { _ in },
            onRetry: { _ in },
            onUploadMore: {},
            onRetryFailed: {},
            onClear: {},
            onMinimize: rows.isEmpty ? nil : {},
            onClose: {}
        )
        .padding(.space40)
    }

    #Preview("Queue") {
        queuePreview([
            TransferQueueRow(id: UUID(), name: "notes.txt", status: .done("Projects"), subtitle: "2 KB"),
            TransferQueueRow(
                id: UUID(),
                name: "beach.jpg",
                status: .running(progress: 0.42, detail: "12s left"),
                subtitle: "4.2 MB"
            ),
            TransferQueueRow(id: UUID(), name: "itinerary.pdf", status: .waiting),
            TransferQueueRow(id: UUID(), name: "movie.mkv", status: .failed("The connection was lost.")),
        ])
    }

    #Preview("Empty") {
        queuePreview([])
    }

    #Preview("Light, no failures") {
        queuePreview([
            TransferQueueRow(id: UUID(), name: "budget.xlsx", status: .done("Projects")),
            TransferQueueRow(
                id: UUID(),
                name: "logo-final.png",
                status: .running(progress: 0.65, detail: nil)
            ),
        ], failure: nil)
            .preferredColorScheme(.light)
    }
#endif
