#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Mac's stand in for pull to refresh, which a Mac list does not have: a toolbar button
    /// running the same refresh, spinning while it runs.
    struct MacRefreshToolbarButton: View {
        let onRefresh: @Sendable () async -> Void
        let onFinished: () -> Void

        @State private var isRefreshing = false

        var body: some View {
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await onRefresh()
                    isRefreshing = false
                    onFinished()
                }
            } label: {
                if isRefreshing {
                    DSSpinner()
                        .controlSize(.small)
                } else {
                    IconKit.retry
                        .foregroundStyle(Color.primaryDS)
                }
            }
            .disabled(isRefreshing)
            .accessibilityLabelWithTooltip(L10n.Menu.refresh)
        }
    }
#endif
