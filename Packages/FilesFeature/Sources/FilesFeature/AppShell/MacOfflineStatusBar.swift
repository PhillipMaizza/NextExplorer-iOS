#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        /// A run shorter than this never shows the bar, so a quick pin does not flash it.
        static let showDelay: Duration = .milliseconds(700)
        static let progressWidth: CGFloat = 180
    }

    /// A run making files available offline, as a status bar along the bottom of the window, like
    /// Finder's: what is downloading, the progress, how many files, and Cancel. A failed run says
    /// why, with Retry and Clear.
    struct MacOfflineStatusBar: ViewModifier {
        let store: StoreOf<MainTabFeature>
        /// Set once a run has lasted `showDelay`; a failure shows at once.
        @State private var isRunShown = false

        private var isFailed: Bool {
            if case .failed = store.offlineProgress.phase {
                true
            } else {
                false
            }
        }

        private var isVisible: Bool {
            store.isOfflineBarVisible && (isFailed || isRunShown)
        }

        func body(content: Content) -> some View {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isVisible {
                        MacOfflineStatusBarContent(store: store)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isVisible)
                .task(id: store.offlineProgress.isActive) {
                    guard store.offlineProgress.isActive else {
                        isRunShown = false
                        return
                    }
                    try? await Task.sleep(for: Metrics.showDelay)
                    // A run that ended, or a view that went away, shows nothing.
                    guard !Task.isCancelled, store.offlineProgress.isActive else { return }
                    isRunShown = true
                }
        }
    }

    struct MacOfflineStatusBarContent: View {
        let store: StoreOf<MainTabFeature>

        private var titles: TransferStatusBars {
            TransferStatusBars(store: store)
        }

        var body: some View {
            let progress = store.offlineProgress
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: .space12) {
                    if case let .failed(message) = progress.phase {
                        IconKit.error.foregroundStyle(Color.negativeText)
                        Text(message).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Button(L10n.Common.clear) { store.send(.offline(.dismissStatusTapped), animation: .default) }
                        Button(L10n.Common.retry) { store.send(.offline(.resyncTapped), animation: .default) }
                    } else {
                        IconKit.availableOffline.foregroundStyle(Color.accent)
                        Text(titles.offlineBarTitle).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if progress.phase == .downloading {
                            Text(L10n.Offline.progressCount(progress.currentFileNumber, progress.filesTotal))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Group {
                            if let fraction = titles.offlineBarProgress {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView().progressViewStyle(.linear)
                            }
                        }
                        .frame(width: Metrics.progressWidth)
                        Button(L10n.Common.cancel) { store.send(.offline(.cancelTapped), animation: .default) }
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, .space16)
                .padding(.vertical, .space8)
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
        }
    }

    @MainActor
    private func statusBarPreviewStore(_ phase: OfflineDownloadProgress.Phase) -> StoreOf<MainTabFeature> {
        var state = MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com")
        )
        state.$offlineProgress.withLock {
            $0 = OfflineDownloadProgress()
            $0.phase = phase
            $0.currentName = "Trip plan.pdf"
            $0.filesDone = 2
            $0.unitsDone = 2.5
            $0.filesTotal = 12
        }
        return Store(initialState: state) { EmptyReducer() }
    }

    #Preview("Downloading") {
        MacOfflineStatusBarContent(store: statusBarPreviewStore(.downloading))
            .frame(width: 720)
    }

    #Preview("Preparing") {
        MacOfflineStatusBarContent(store: statusBarPreviewStore(.preparing))
            .frame(width: 720)
    }

    #Preview("Failed") {
        MacOfflineStatusBarContent(
            store: statusBarPreviewStore(.failed("You're offline. Connect to the internet and try again."))
        )
        .frame(width: 720)
    }
#endif
