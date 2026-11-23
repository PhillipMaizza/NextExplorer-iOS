#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listHeight: CGFloat = 240
        static let rowHeight: CGFloat = .size32
        static let barWidth: CGFloat = .size96
    }

    /// The upload or download queue as a Mac sheet: the items in a list box with their progress
    /// and Cancel or Try Again, then Clear and Done.
    struct MacTransferQueueSheet: View {
        let title: String
        let rows: [TransferQueueRow]
        let emptyMessage: String
        let canClear: Bool
        let onCancel: (UUID) -> Void
        let onRetry: (UUID) -> Void
        let onClear: () -> Void
        let onClose: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                Text(title).type(.headline4)
                VStack(spacing: .zero) {
                    HStack {
                        Text(L10n.Sort.name)
                        Spacer(minLength: .space8)
                        Text(L10n.MacSettings.status)
                    }
                    .type(.caption(.semibold), style: .secondary)
                    .macListRow(isSelected: false)
                    if rows.isEmpty {
                        Text(emptyMessage)
                            .type(.body2(.regular), style: .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: .zero) {
                                ForEach(rows) { row in
                                    rowView(row)
                                }
                            }
                        }
                    }
                }
                .frame(height: Metrics.listHeight, alignment: .top)
                .macListBox()
                HStack(spacing: .space8) {
                    Spacer()
                    Button(L10n.Uploads.clear, action: onClear)
                        .buttonStyle(.macDS(.secondary))
                        .disabled(!canClear)
                    Button(L10n.Common.done, action: onClose)
                        .buttonStyle(.macDS(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.space24)
            .frame(width: MacFormSheetMetrics.width)
            .onExitCommand(perform: onClose)
        }

        private func rowView(_ row: TransferQueueRow) -> some View {
            HStack(spacing: .space8) {
                Text(row.name)
                    .type(.body2(.regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: .space8)
                status(row)
            }
            .foregroundStyle(Color.macChromeText)
            .frame(minHeight: Metrics.rowHeight)
            .macListRow(isSelected: false)
        }

        @ViewBuilder
        private func status(_ row: TransferQueueRow) -> some View {
            switch row.status {
            case .waiting:
                Text(L10n.Uploads.statusWaiting).type(.body3(.regular), style: .secondary)
                cancelButton(row)
            case let .running(progress, detail):
                if let detail {
                    Text(detail)
                        .type(.caption(.regular), style: .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                MacProgressBar(value: progress)
                    .frame(width: Metrics.barWidth)
                cancelButton(row)
            case let .done(text):
                Text(text).type(.body3(.regular), style: .secondary).lineLimit(1)
            case let .failed(message):
                Text(message)
                    .type(.body3(.regular), style: .error)
                    .lineLimit(1)
                    .help(message)
                Button(L10n.Common.retry) { onRetry(row.id) }
                    .buttonStyle(.macDS(.secondary, size: .small))
            }
        }

        private func cancelButton(_ row: TransferQueueRow) -> some View {
            MacRowRemoveButton(label: L10n.Common.cancel) { onCancel(row.id) }
        }
    }

    @MainActor
    private func queuePreview(_ rows: [TransferQueueRow]) -> some View {
        MacTransferQueueSheet(
            title: "Uploads",
            rows: rows,
            emptyMessage: "No uploads",
            canClear: !rows.isEmpty,
            onCancel: { _ in },
            onRetry: { _ in },
            onClear: {},
            onClose: {}
        )
    }

    #Preview("Queue") {
        queuePreview([
            TransferQueueRow(
                id: UUID(),
                name: "beach.jpg",
                status: .running(progress: 0.42, detail: "1.2 MB of 2.8 MB")
            ),
            TransferQueueRow(id: UUID(), name: "itinerary.pdf", status: .waiting),
            TransferQueueRow(id: UUID(), name: "notes.txt", status: .done("Uploaded")),
            TransferQueueRow(id: UUID(), name: "movie.mkv", status: .failed("The connection was lost.")),
        ])
    }

    #Preview("Empty") {
        queuePreview([])
    }
#endif
