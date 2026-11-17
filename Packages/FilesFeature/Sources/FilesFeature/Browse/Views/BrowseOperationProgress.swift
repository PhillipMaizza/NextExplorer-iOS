import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The running bulk delete, shown the way downloads are: a floating pill above the tab bar on iOS,
/// a status bar along the bottom of the content on the Mac, each with Cancel.
struct BrowseDeleteProgress: ViewModifier {
    /// A delete shorter than this never shows the bar, so a quick one does not flash it.
    private static let showDelay: Duration = .milliseconds(700)

    let store: StoreOf<BrowseFeature>
    /// What the floating pill clears at the bottom (the tab bar, a path bar).
    let bottomInset: CGFloat
    /// Only the list shows it: a preview cover has its own chrome.
    let isEnabled: Bool
    @State private var isRunShown = false

    private var visibleProgress: Double? {
        isEnabled && isRunShown ? store.bulkDeleteProgress : nil
    }

    func body(content: Content) -> some View {
        placed(content)
            .task(id: store.bulkDeleteProgress != nil) {
                guard store.bulkDeleteProgress != nil else {
                    isRunShown = false
                    return
                }
                try? await Task.sleep(for: Self.showDelay)
                guard !Task.isCancelled, store.bulkDeleteProgress != nil else { return }
                isRunShown = true
            }
    }

    @ViewBuilder
    private func placed(_ content: Content) -> some View {
        #if os(iOS)
            content
                .overlay(alignment: .bottom) {
                    if let progress = visibleProgress {
                        BrowseDeleteProgressPill(progress: progress) { store.send(.bulkDeleteCancelTapped) }
                            .padding(.horizontal, .space16)
                            .padding(.bottom, bottomInset + .space8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DSMotion.stateFade, value: visibleProgress != nil)
        #elseif os(macOS)
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let progress = visibleProgress {
                        BrowseDeleteStatusBar(progress: progress) { store.send(.bulkDeleteCancelTapped) }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DSMotion.stateFade, value: visibleProgress != nil)
        #endif
    }
}

#if os(iOS)
    struct BrowseDeleteProgressPill: View {
        let progress: Double
        let onCancel: () -> Void

        var body: some View {
            TransferProgressBar(
                icon: IconKit.delete,
                title: L10n.Browse.progressDeleting,
                progress: progress,
                detail: progress.formatted(.percent.precision(.fractionLength(0))),
                cancelLabel: L10n.Common.cancel,
                onTap: {},
                onCancelAll: onCancel
            )
        }
    }

    #Preview("Delete pill, running") {
        BrowseDeleteProgressPill(progress: 0.4) {}
            .padding()
    }

    #Preview("Delete pill, starting") {
        BrowseDeleteProgressPill(progress: 0) {}
            .padding()
    }
#endif

#if os(macOS)
    struct BrowseDeleteStatusBar: View {
        private static let progressWidth: CGFloat = 180

        let progress: Double
        let onCancel: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: .space12) {
                    IconKit.delete.foregroundStyle(Color.accent)
                    Text(L10n.Browse.progressDeleting).lineLimit(1)
                    Spacer()
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(Color.secondaryDS)
                        .monospacedDigit()
                    ProgressView(value: progress)
                        .tint(Color.accent)
                        .accessibilityLabel(L10n.Browse.progressDeleting)
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
        BrowseDeleteStatusBar(progress: 0.4) {}
            .frame(width: 640)
    }

    #Preview("Delete bar, starting") {
        BrowseDeleteStatusBar(progress: 0) {}
            .frame(width: 640)
    }
#endif
