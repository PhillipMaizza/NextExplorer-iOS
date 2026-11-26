#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let offlineShowDelay: Duration = .milliseconds(700)
    }

    @MainActor
    struct MacDownloadActivity {
        static let offlineRowID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0F, 0xF1))

        let store: StoreOf<MainTabFeature>
        let locale: Locale

        private var queue: DownloadQueueFeature.State {
            store.downloadQueue
        }

        private var offline: OfflineDownloadProgress {
            store.offlineProgress
        }

        private var titles: TransferStatusBars {
            TransferStatusBars(store: store)
        }

        var isActive: Bool {
            queue.isActive || offline.isActive
        }

        var offlineFailure: String? {
            guard case let .failed(message) = offline.phase else { return nil }
            return message
        }

        var hasFailures: Bool {
            queue.failedCount > 0 || offlineFailure != nil
        }

        var title: String {
            if queue.isActive {
                return titles.downloadBarTitle
            }
            return offline.isActive ? titles.offlineBarTitle : failureTitle
        }

        var failureTitle: String {
            queue.failedCount > 0 ? TransferFailureText.downloads(queue.failedCount) : offlineFailure ?? ""
        }

        var fileName: String? {
            if queue.isActive {
                return queue.currentJob?.fileName
            }
            return offline.currentName.isEmpty ? nil : offline.currentName
        }

        var fraction: Double? {
            queue.isActive ? queue.currentJob?.progress : titles.offlineBarProgress
        }

        var timeLeft: String? {
            if queue.isActive {
                return DownloadProgressText.timeLeft(queue.currentJob?.estimatedSecondsRemaining, locale: locale)
            }
            return offlineTimeLeft
        }

        private var offlineTimeLeft: String? {
            DownloadProgressText.timeLeft(offline.secondsRemaining(now: .now), locale: locale)
        }

        var offlineRow: TransferQueueRow? {
            guard offline.phase.shouldShowOfflineBar || offline.phase == .waitingForNetwork else { return nil }
            let status: TransferQueueRow.Status = switch offline.phase {
            case let .failed(message): .failed(message)
            case .downloading: .running(progress: offline.fractionComplete, detail: offlineTimeLeft)
            case .preparing: .running(progress: nil, detail: nil)
            case .idle, .completed, .waitingForNetwork: .waiting
            }
            return TransferQueueRow(
                id: Self.offlineRowID,
                name: titles.offlineBarTitle,
                status: status,
                subtitle: offline.phase == .downloading
                    ? L10n.Offline.progressCount(offline.currentFileNumber, offline.filesTotal)
                    : nil
            )
        }

        func cancel() {
            if queue.isActive {
                store.send(.downloadQueue(.cancelAllTapped))
            }
            if offline.isActive {
                store.send(.offline(.cancelTapped), animation: DSMotion.stateFade)
            }
        }

        func clear() {
            store.send(.downloadQueue(.clearFinishedTapped))
            if offlineFailure != nil {
                store.send(.offline(.dismissStatusTapped), animation: DSMotion.stateFade)
            }
        }

        func retry() {
            if queue.failedCount > 0 {
                store.send(.downloadQueue(.retryAllFailedTapped))
            }
            if offlineFailure != nil {
                store.send(.offline(.resyncTapped), animation: DSMotion.stateFade)
            }
        }

        func cancelOfflineRow() {
            store.send(.offline(offline.isActive ? .cancelTapped : .dismissStatusTapped), animation: DSMotion.listDiff)
        }

        func retryOfflineRow() {
            store.send(.offline(.resyncTapped), animation: DSMotion.listDiff)
        }

        var offlineSummary: TransferQueueSummary {
            let done = switch offline.phase {
            case .downloading: L10n.Offline.progressCount(offline.currentFileNumber, offline.filesTotal)
            case .preparing: L10n.Offline.preparing
            case .idle, .completed, .waitingForNetwork, .failed: ""
            }
            return TransferQueueSummary(done: done, failure: offlineFailure, timeLeft: offlineTimeLeft)
        }

        func showAll() {
            store.send(.downloadQueue(.barTapped))
        }

        func notification(onShowAll: @escaping () -> Void) -> DSToastMessage? {
            guard isActive, !queue.isSheetPresented else { return nil }
            return .transfer(
                title,
                id: TransferQueue.downloads.rawValue,
                icon: IconKit.downloadFill,
                fraction: fraction,
                fileName: fileName,
                timeLeft: timeLeft,
                hasFailures: hasFailures,
                actionTitle: L10n.Menu.showAll,
                action: {
                    onShowAll()
                    showAll()
                },
                cancelTitle: L10n.DownloadQueue.cancelAll,
                cancel: cancel
            )
        }
    }

    enum MacMainWindow {
        @MainActor
        static func bringForward() {
            NSApp.windows
                .first { $0.isVisible && $0.canBecomeMain && $0 !== NSApp.keyWindow && $0.title != L10n.Menu.about }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private struct MacDownloadActivityVisibility: ViewModifier {
        let store: StoreOf<MainTabFeature>
        @Binding var isVisible: Bool
        @State private var isOfflineRunShown = false

        private var isOfflineVisible: Bool {
            switch store.offlineProgress.phase {
            case .failed: true
            case .preparing, .downloading: isOfflineRunShown
            case .idle, .completed, .waitingForNetwork: false
            }
        }

        private var shouldShow: Bool {
            store.downloadQueue.isBarVisible || isOfflineVisible
        }

        func body(content: Content) -> some View {
            content
                .onChange(of: shouldShow, initial: true) { _, visible in isVisible = visible }
                .task(id: store.offlineProgress.isActive) {
                    guard store.offlineProgress.isActive else {
                        isOfflineRunShown = false
                        return
                    }
                    try? await Task.sleep(for: Metrics.offlineShowDelay)
                    guard !Task.isCancelled, store.offlineProgress.isActive else { return }
                    isOfflineRunShown = true
                }
        }
    }

    extension View {
        func macDownloadActivityVisible(_ store: StoreOf<MainTabFeature>, isVisible: Binding<Bool>) -> some View {
            modifier(MacDownloadActivityVisibility(store: store, isVisible: isVisible))
        }
    }
#endif
