#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// The Mac's stand in for pull to refresh, which a Mac list does not have: publishes the
        /// refresh the window's toolbar button (`macWindowToolbar`) and View › Refresh (⌘R) both
        /// run, so either dims the button and toasts alike.
        func macToolbarRefresh(
            onRefresh: @escaping @Sendable () async -> Void,
            onFinished: @escaping () -> Void
        ) -> some View {
            modifier(MacToolbarRefresh(onRefresh: onRefresh, onFinished: onFinished))
        }
    }

    private struct MacToolbarRefresh: ViewModifier {
        let onRefresh: @Sendable () async -> Void
        let onFinished: () -> Void

        @State private var isRefreshing = false

        func body(content: Content) -> some View {
            content
                // Published from the screen rather than the button: a toolbar item is hosted
                // outside the window's view tree, so a value set there never reached ⌘R.
                .focusedSceneValue(
                    \.refreshVisibleScreen,
                    RefreshScreenAction(isRefreshing: isRefreshing, perform: refresh)
                )
        }

        private func refresh() {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task {
                await onRefresh()
                isRefreshing = false
                onFinished()
            }
        }
    }

    struct MacRefreshToolbarButton: View {
        let isRefreshing: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) { IconKit.macToolbarRefresh.macToolbarGlyph() }
                .buttonStyle(.macToolbarCircle)
                .disabled(isRefreshing)
                .accessibilityLabelWithTooltip(L10n.Menu.refresh)
        }
    }

    /// ⌘R for the section on screen, published by its toolbar refresh.
    public struct RefreshScreenAction {
        let isRefreshing: Bool
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var refreshVisibleScreen: RefreshScreenAction?
    }

    #Preview {
        NavigationStack {
            Text(verbatim: "Folder contents")
                .previewCanvas(.dialog)
                .macToolbarRefresh(onRefresh: { try? await Task.sleep(for: .seconds(2)) }, onFinished: {})
        }
        .macWindowToolbar()
    }
#endif
