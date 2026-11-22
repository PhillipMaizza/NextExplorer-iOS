#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 560
        static let height: CGFloat = 420
        static let statusColumnWidth: CGFloat = 190
        static let actionColumnWidth: CGFloat = 70
        static let iconSize: CGFloat = 16
    }

    /// The upload or download queue as a native Mac sheet: a table of items with their
    /// progress and Cancel or Retry, then Clear and Done.
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
            VStack(alignment: .leading, spacing: .space12) {
                Text(title).font(.headline)
                Table(rows) {
                    TableColumn(L10n.Sort.name) { row in
                        Label {
                            Text(row.name).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(nsImage: MacFileTypeIcon.image(forFileName: row.name))
                                .resizable()
                                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                                .accessibilityHidden(true)
                        }
                    }
                    TableColumn(L10n.MacSettings.status) { row in status(row.status) }
                        .width(Metrics.statusColumnWidth)
                    TableColumn("") { row in action(row) }
                        .width(Metrics.actionColumnWidth)
                }
                .overlay {
                    if rows.isEmpty {
                        Text(emptyMessage).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(L10n.Uploads.clear, action: onClear)
                        .disabled(!canClear)
                    Spacer()
                    Button(L10n.Common.done, action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.space24)
            .frame(width: Metrics.width, height: Metrics.height)
            // Esc closes it like any Mac dialog; Done keeps Return.
            .onExitCommand(perform: onClose)
        }

        @ViewBuilder
        private func status(_ status: TransferQueueRow.Status) -> some View {
            switch status {
            case .waiting:
                Text(L10n.Uploads.statusWaiting).foregroundStyle(.secondary)
            case let .running(progress, detail):
                VStack(alignment: .leading, spacing: .space2) {
                    MacProgressBar(value: progress)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                }
            case let .done(text):
                Label { Text(text) } icon: { IconKit.checkmarkCircleFill }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case let .failed(message):
                Label { Text(message) } icon: { IconKit.errorFill }
                    .foregroundStyle(Color.negativeText)
                    .lineLimit(1)
            }
        }

        @ViewBuilder
        private func action(_ row: TransferQueueRow) -> some View {
            switch row.status {
            case .waiting, .running:
                Button(L10n.Common.cancel) { onCancel(row.id) }.controlSize(.small)
            case .failed:
                Button(L10n.Common.retry) { onRetry(row.id) }.controlSize(.small)
            case .done:
                EmptyView()
            }
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
