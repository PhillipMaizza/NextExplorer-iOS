#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI
    import UserNotifications

    private enum Metrics {
        static let popoverWidth: CGFloat = 340
        static let ringSize: CGFloat = 16
        static let ringLineWidth: CGFloat = 2.5
        /// The progress ring sits just outside the glyph.
        static let ringFrameSize: CGFloat = ringSize + .size6
    }

    /// Uploads and downloads on the Mac: a toolbar button with a progress ring, like Safari's
    /// downloads, opening a popover with each queue's progress and actions. It replaces the
    /// floating bars iOS shows over the content.
    struct MacTransferActivityButton: View {
        let store: StoreOf<MainTabFeature>
        @State private var isShowingPopover = false

        private var progress: Double? {
            if store.uploads.isActive {
                return store.uploads.overallProgress
            }
            if store.downloadQueue.isActive {
                return store.downloadQueue.currentJob?.progress
            }
            return nil
        }

        private var hasFailures: Bool {
            store.uploads.failedCount + store.downloadQueue.failedCount > 0
        }

        private var accessibilityStatus: String {
            if let progress {
                return progress.formatted(.percent.precision(.fractionLength(0)))
            }
            if store.uploads.failedCount > 0 {
                return TransferFailureText.uploads(store.uploads.failedCount)
            }
            if store.downloadQueue.failedCount > 0 {
                return TransferFailureText.downloads(store.downloadQueue.failedCount)
            }
            return ""
        }

        var body: some View {
            Button { isShowingPopover.toggle() } label: {
                ZStack {
                    (hasFailures && progress == nil ? IconKit.error : IconKit.transfers)
                        .foregroundStyle(hasFailures && progress == nil ? Color.negativeText : Color.primary)
                    if let progress {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Metrics.ringLineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: Metrics.ringFrameSize, height: Metrics.ringFrameSize)
                    }
                }
            }
            .accessibilityLabelWithTooltip(L10n.Menu.activity)
            // The ring and the error glyph only show it, so VoiceOver hears the same state.
            .accessibilityValue(accessibilityStatus)
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                MacTransferActivityPopover(store: store)
            }
        }
    }

    private struct MacTransferActivityPopover: View {
        let store: StoreOf<MainTabFeature>

        private var titles: TransferStatusBars {
            TransferStatusBars(store: store)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space12) {
                if store.uploads.isBarVisible {
                    queueRow(
                        icon: IconKit.upload,
                        isActive: store.uploads.isActive,
                        title: titles.uploadBarTitle,
                        progress: store.uploads.overallProgress,
                        failedLabel: TransferFailureText.uploads(store.uploads.failedCount),
                        cancelTitle: L10n.Uploads.cancelAll,
                        onCancel: { store.send(.uploads(.cancelAllTapped)) },
                        onRetry: { store.send(.uploads(.retryAllFailedTapped)) },
                        onClear: { store.send(.uploads(.clearFinishedTapped)) },
                        onShowAll: { store.send(.uploads(.barTapped)) }
                    )
                }
                if store.uploads.isBarVisible, store.downloadQueue.isBarVisible {
                    Divider()
                }
                if store.downloadQueue.isBarVisible {
                    let queue = store.downloadQueue
                    queueRow(
                        icon: IconKit.download,
                        isActive: queue.isActive,
                        title: titles.downloadBarTitle,
                        progress: queue.currentJob?.progress,
                        failedLabel: TransferFailureText.downloads(queue.failedCount),
                        cancelTitle: L10n.DownloadQueue.cancelAll,
                        onCancel: { store.send(.downloadQueue(.cancelAllTapped)) },
                        onRetry: { store.send(.downloadQueue(.retryAllFailedTapped)) },
                        onClear: { store.send(.downloadQueue(.clearFinishedTapped)) },
                        onShowAll: { store.send(.downloadQueue(.barTapped)) }
                    )
                }
            }
            .padding(.space16)
            .frame(width: Metrics.popoverWidth)
        }

        // swiftlint:disable:next function_parameter_count
        private func queueRow(
            icon: Image,
            isActive: Bool,
            title: String,
            progress: Double?,
            failedLabel: String,
            cancelTitle: String,
            onCancel: @escaping () -> Void,
            onRetry: @escaping () -> Void,
            onClear: @escaping () -> Void,
            onShowAll: @escaping () -> Void
        ) -> some View {
            VStack(alignment: .leading, spacing: .space8) {
                Label {
                    Text(isActive ? title : failedLabel).lineLimit(1).truncationMode(.middle)
                } icon: {
                    (isActive ? icon : IconKit.error)
                        .foregroundStyle(isActive ? Color.accentColor : Color.negativeText)
                }
                if isActive {
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                HStack {
                    Button(L10n.Menu.showAll, action: onShowAll)
                    Spacer()
                    if isActive {
                        Button(cancelTitle, action: onCancel)
                    } else {
                        Button(L10n.Common.clear, action: onClear)
                        Button(L10n.Common.retry, action: onRetry)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    /// "1 upload failed" or "N uploads failed", and the same for downloads.
    private enum TransferFailureText {
        static func uploads(_ count: Int) -> String {
            count == 1 ? L10n.Uploads.barFailedOne : L10n.Uploads.barFailedMany(count)
        }

        static func downloads(_ count: Int) -> String {
            count == 1 ? L10n.DownloadQueue.barFailedOne : L10n.DownloadQueue.barFailedMany(count)
        }
    }

    /// A system notification when the upload or download queue finishes while the app is in
    /// the background, so a long transfer needs no watching.
    struct MacTransferNotifications: ViewModifier {
        let uploadsRemaining: Int
        let uploadsFailed: Int
        let downloadsRemaining: Int
        let downloadsFailed: Int

        @State private var uploadBatch = 0
        @State private var downloadBatch = 0

        func body(content: Content) -> some View {
            content
                .onChange(of: uploadsRemaining) { old, new in
                    uploadBatch = finished(old: old, new: new, batch: uploadBatch) { count in
                        notify(
                            title: uploadsFailed > 0 ? TransferFailureText.uploads(uploadsFailed) : L10n.Uploads.notifyDone,
                            body: L10n.Uploads.notifyBody(count)
                        )
                    }
                }
                .onChange(of: downloadsRemaining) { old, new in
                    downloadBatch = finished(old: old, new: new, batch: downloadBatch) { count in
                        notify(
                            title: downloadsFailed > 0 ? TransferFailureText.downloads(downloadsFailed) : L10n.DownloadQueue.notifyDone,
                            body: count == 1 ? L10n.DownloadQueue.savedOne : L10n.DownloadQueue.savedMany(count)
                        )
                    }
                }
        }

        /// Tracks the largest queue seen this run; once it drains, reports that many and resets.
        private func finished(old: Int, new: Int, batch: Int, onDone: (Int) -> Void) -> Int {
            if new > 0 {
                if old == 0 {
                    requestAuthorization()
                }
                return max(batch, new)
            }
            if old > 0, batch > 0 {
                onDone(batch)
            }
            return 0
        }

        private func requestAuthorization() {
            // Nonisolated: the callback arrives on a background queue.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
        }

        private func notify(title: String, body: String) {
            guard !NSApp.isActive else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    @MainActor
    private func transferPreviewStore() -> StoreOf<MainTabFeature> {
        Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com")
        )) { MainTabFeature() } withDependencies: { $0.filesClient = .previewValue }
    }

    #Preview("Activity button") {
        MacTransferActivityButton(store: transferPreviewStore())
            .padding(.space24)
    }

    #Preview("Notifications") {
        Text(verbatim: "Finished transfers notify while the app is in the background")
            .padding(.space24)
            .modifier(MacTransferNotifications(uploadsRemaining: 0, uploadsFailed: 0, downloadsRemaining: 0, downloadsFailed: 0))
    }
#endif
