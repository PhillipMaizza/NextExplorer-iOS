import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// What the bar shows for the running bulk delete, copy or move.
struct BrowseRunningOperation {
    let title: String
    let icon: Image
    let progress: Double
    let cancelAction: BrowseFeature.Action

    init?(_ state: BrowseFeature.State) {
        if let progress = state.bulkDeleteProgress {
            self.init(
                title: L10n.Browse.progressDeleting,
                icon: IconKit.delete,
                progress: progress,
                cancelAction: .bulkDeleteCancelTapped
            )
        } else if let progress = state.transferProgress {
            let isMove = state.pendingTransferRetry?.operation == .move
            self.init(
                title: isMove ? L10n.Browse.progressMoving : L10n.Browse.progressCopying,
                icon: isMove ? IconKit.move : IconKit.copy,
                progress: progress,
                cancelAction: .transferCancelTapped
            )
        } else {
            return nil
        }
    }

    init(title: String, icon: Image, progress: Double, cancelAction: BrowseFeature.Action) {
        self.title = title
        self.icon = icon
        self.progress = progress
        self.cancelAction = cancelAction
    }
}

/// The running bulk delete, copy or move, shown the way downloads are: a floating pill above the tab bar
/// on iOS, a status bar along the bottom of the content on the Mac, each with Cancel.
struct BrowseOperationProgress: ViewModifier {
    /// An operation shorter than this never shows the bar, so a quick one does not flash it.
    private static let showDelay: Duration = .milliseconds(700)

    let store: StoreOf<BrowseFeature>
    /// What the floating pill clears at the bottom (the tab bar, a path bar).
    let bottomInset: CGFloat
    /// Only the frontmost surface shows it, the list or the preview cover over it.
    let isEnabled: Bool
    @State private var isRunShown = false

    private var running: BrowseRunningOperation? {
        BrowseRunningOperation(store.state)
    }

    private var visibleRun: BrowseRunningOperation? {
        isEnabled && isRunShown ? running : nil
    }

    func body(content: Content) -> some View {
        placed(content)
            .task(id: running != nil) {
                guard running != nil else {
                    isRunShown = false
                    return
                }
                try? await Task.sleep(for: Self.showDelay)
                guard !Task.isCancelled, running != nil else { return }
                isRunShown = true
            }
    }

    @ViewBuilder
    private func placed(_ content: Content) -> some View {
        #if os(iOS)
            content
                .overlay(alignment: .bottom) {
                    if let run = visibleRun {
                        BrowseOperationPill(run: run) { store.send(run.cancelAction) }
                            .padding(.horizontal, .space16)
                            .padding(.bottom, bottomInset + .space8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DSMotion.stateFade, value: visibleRun != nil)
        #elseif os(macOS)
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let run = visibleRun {
                        BrowseOperationStatusBar(run: run) { store.send(run.cancelAction) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DSMotion.stateFade, value: visibleRun != nil)
        #endif
    }
}

#if os(iOS)
    struct BrowseOperationPill: View {
        let run: BrowseRunningOperation
        let onCancel: () -> Void

        var body: some View {
            TransferProgressBar(
                icon: run.icon,
                title: run.title,
                progress: run.progress,
                detail: run.progress.formatted(.percent.precision(.fractionLength(0))),
                cancelLabel: L10n.Common.cancel,
                onTap: {},
                onCancelAll: onCancel
            )
        }
    }

    #Preview("Delete pill, running") {
        BrowseOperationPill(run: .previewDelete(0.4)) {}
            .padding()
    }

    #Preview("Copy pill, starting") {
        BrowseOperationPill(run: .previewCopy(0)) {}
            .padding()
    }

    #Preview("Move pill, running") {
        BrowseOperationPill(run: .previewMove(0.7)) {}
            .padding()
    }
#endif

#if os(macOS)
    struct BrowseOperationStatusBar: View {
        private static let progressWidth: CGFloat = 180

        let run: BrowseRunningOperation
        let onCancel: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: .space12) {
                    run.icon.foregroundStyle(Color.accent)
                    Text(run.title).lineLimit(1)
                    Spacer()
                    Text(run.progress.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(Color.secondaryDS)
                        .monospacedDigit()
                    ProgressView(value: run.progress)
                        .tint(Color.accent)
                        .accessibilityLabel(run.title)
                        .frame(width: Self.progressWidth)
                    Button(L10n.Common.cancel, action: onCancel)
                }
                .controlSize(.small)
                .padding(.horizontal, .space16)
                .padding(.vertical, .space8)
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
        }
    }

    #Preview("Delete bar, running") {
        BrowseOperationStatusBar(run: .previewDelete(0.4)) {}
            .frame(width: 640)
    }

    #Preview("Copy bar, starting") {
        BrowseOperationStatusBar(run: .previewCopy(0)) {}
            .frame(width: 640)
    }

    #Preview("Move bar, running") {
        BrowseOperationStatusBar(run: .previewMove(0.7)) {}
            .frame(width: 640)
    }
#endif

extension BrowseRunningOperation {
    static func previewDelete(_ progress: Double) -> Self {
        Self(
            title: L10n.Browse.progressDeleting,
            icon: IconKit.delete,
            progress: progress,
            cancelAction: .bulkDeleteCancelTapped
        )
    }

    static func previewCopy(_ progress: Double) -> Self {
        Self(
            title: L10n.Browse.progressCopying,
            icon: IconKit.copy,
            progress: progress,
            cancelAction: .transferCancelTapped
        )
    }

    static func previewMove(_ progress: Double) -> Self {
        Self(
            title: L10n.Browse.progressMoving,
            icon: IconKit.move,
            progress: progress,
            cancelAction: .transferCancelTapped
        )
    }
}
