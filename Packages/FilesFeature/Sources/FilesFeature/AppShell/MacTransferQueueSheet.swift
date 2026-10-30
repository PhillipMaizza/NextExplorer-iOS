#if os(macOS)
    import AppKit
    import DesignSystem
    import Localization
    import SwiftUI
    import UniformTypeIdentifiers

    private enum Metrics {
        static let width: CGFloat = 560
        static let height: CGFloat = 420
        static let statusColumnWidth: CGFloat = 190
        static let actionColumnWidth: CGFloat = 70
        static let iconSize: CGFloat = 16
    }

    /// One row of a transfer queue, whichever queue it comes from.
    struct MacTransferRow: Identifiable {
        enum Status {
            case waiting
            case running(progress: Double?, detail: String?)
            case done(String)
            case failed(String)
        }

        let id: UUID
        let name: String
        let status: Status
    }

    /// The upload or download queue as a native Mac sheet: a table of items with their
    /// progress and Cancel or Retry, then Clear and Done.
    struct MacTransferQueueSheet: View {
        let title: String
        let rows: [MacTransferRow]
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
                            Image(nsImage: Self.icon(for: row.name))
                                .resizable()
                                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
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
        }

        @ViewBuilder
        private func status(_ status: MacTransferRow.Status) -> some View {
            switch status {
            case .waiting:
                Text(L10n.Uploads.statusWaiting).foregroundStyle(.secondary)
            case let .running(progress, detail):
                VStack(alignment: .leading, spacing: .space2) {
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
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
        private func action(_ row: MacTransferRow) -> some View {
            switch row.status {
            case .waiting, .running:
                Button(L10n.Common.cancel) { onCancel(row.id) }.controlSize(.small)
            case .failed:
                Button(L10n.Common.retry) { onRetry(row.id) }.controlSize(.small)
            case .done:
                EmptyView()
            }
        }

        private static func icon(for name: String) -> NSImage {
            let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
            return NSWorkspace.shared.icon(for: type)
        }
    }

    @MainActor
    private func queuePreview(_ rows: [MacTransferRow]) -> some View {
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
            MacTransferRow(id: UUID(), name: "beach.jpg", status: .running(progress: 0.42, detail: "1.2 MB of 2.8 MB")),
            MacTransferRow(id: UUID(), name: "itinerary.pdf", status: .waiting),
            MacTransferRow(id: UUID(), name: "notes.txt", status: .done("Uploaded")),
            MacTransferRow(id: UUID(), name: "movie.mkv", status: .failed("The connection was lost.")),
        ])
    }

    #Preview("Empty") {
        queuePreview([])
    }
#endif
