#if os(iOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let rowIconSize: CGFloat = .iconMedium
        static let rowSpacing: CGFloat = .space12
        static let textSpacing: CGFloat = .space4
        static let controlSize: CGFloat = .iconSmall
        static let progressWidth: CGFloat = 96
    }

    struct PhoneTransferQueueSheet: View {
        let title: String
        let rows: [TransferQueueRow]
        let emptyIcon: Image
        let emptyMessage: String
        let canClear: Bool
        let onCancel: (UUID) -> Void
        let onRetry: (UUID) -> Void
        let onClear: () -> Void
        let onClose: () -> Void

        var body: some View {
            NavigationStack {
                content
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: onClose) {
                                IconKit.close.foregroundStyle(Color.primaryDS)
                            }
                            .accessibilityLabel(L10n.Common.close)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.Uploads.clear, action: onClear)
                                .disabled(!canClear)
                        }
                    }
            }
        }

        @ViewBuilder
        private var content: some View {
            if rows.isEmpty {
                EmptyStateView(icon: emptyIcon, message: emptyMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DSGroupedList(rows) { row($0) }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.backgroundPrimary)
            }
        }

        private func row(_ row: TransferQueueRow) -> some View {
            HStack(spacing: Constants.rowSpacing) {
                FileTypeIcon(kind: (row.name as NSString).pathExtension)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                VStack(alignment: .leading, spacing: Constants.textSpacing) {
                    Text(row.name)
                        .type(.body2(.regular), style: .primaryOnSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    subtitle(row.status)
                }
                Spacer(minLength: Constants.rowSpacing)
                control(row)
            }
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private func subtitle(_ status: TransferQueueRow.Status) -> some View {
            switch status {
            case .waiting:
                Text(L10n.Uploads.statusWaiting).type(.body3(.regular), style: .secondary)
            case let .running(progress, detail):
                VStack(alignment: .leading, spacing: Constants.textSpacing) {
                    Group {
                        if let progress {
                            ProgressView(value: progress).tint(Color.positive)
                        } else {
                            IndeterminateProgressBar()
                        }
                    }
                    .frame(width: Constants.progressWidth)
                    if let detail {
                        Text(detail)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(2)
                            .monospacedDigit()
                    }
                }
            case let .done(text):
                Text(text).type(.body3(.regular), style: .secondary).lineLimit(1)
            case let .failed(message):
                Text(message).type(.body3(.regular), style: .secondary).lineLimit(1)
            }
        }

        @ViewBuilder
        private func control(_ row: TransferQueueRow) -> some View {
            switch row.status {
            case .waiting, .running:
                Button { onCancel(row.id) } label: {
                    icon(IconKit.closeCircle, color: Color.secondaryDS)
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabel(L10n.Common.cancel)
            case .done:
                icon(IconKit.checkmarkCircleFill, color: Color.positive)
            case .failed:
                Button { onRetry(row.id) } label: {
                    icon(IconKit.retry, color: Color.accent)
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabel(L10n.Common.retry)
            }
        }

        private func icon(_ image: Image, color: Color) -> some View {
            image
                .resizable().scaledToFit()
                .foregroundStyle(color)
                .frame(width: Constants.controlSize, height: Constants.controlSize)
        }
    }

    @MainActor
    private func queuePreview(_ rows: [TransferQueueRow]) -> some View {
        PhoneTransferQueueSheet(
            title: L10n.Uploads.navigationTitle,
            rows: rows,
            emptyIcon: IconKit.upload,
            emptyMessage: L10n.Uploads.emptyList,
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
            TransferQueueRow(id: UUID(), name: "Photos", status: .running(progress: nil, detail: "312 MB")),
            TransferQueueRow(id: UUID(), name: "itinerary.pdf", status: .waiting),
            TransferQueueRow(id: UUID(), name: "notes.txt", status: .done("Uploaded")),
            TransferQueueRow(id: UUID(), name: "movie.mkv", status: .failed("The connection was lost.")),
        ])
    }

    #Preview("Empty") {
        queuePreview([])
    }
#endif
