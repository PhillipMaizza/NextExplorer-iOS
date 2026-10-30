#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// The Mac's stand in for pull to refresh, which a Mac list does not have: a toolbar
        /// button running the same refresh, spinning while it runs, and View › Refresh (⌘R)
        /// pressing that same button so it spins and toasts alike.
        func macToolbarRefresh(onRefresh: @escaping @Sendable () async -> Void, onFinished: @escaping () -> Void) -> some View {
            modifier(MacToolbarRefresh(onRefresh: onRefresh, onFinished: onFinished))
        }
    }

    private struct MacToolbarRefresh: ViewModifier {
        let onRefresh: @Sendable () async -> Void
        let onFinished: () -> Void

        @State private var isRefreshing = false

        func body(content: Content) -> some View {
            content
                .toolbar {
                    // Navigation placement shares one glass capsule with Back on a pushed screen;
                    // as a separate primary action the system drew it there without any background.
                    ToolbarItem(placement: .navigation) {
                        MacRefreshToolbarButton(isRefreshing: isRefreshing, action: refresh)
                    }
                }
                // Published from the screen rather than the button: a toolbar item is hosted
                // outside the window's view tree, so a value set there never reached ⌘R.
                .focusedSceneValue(\.refreshVisibleScreen, RefreshScreenAction(perform: refresh))
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

    private struct MacRefreshToolbarButton: View {
        let isRefreshing: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
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

    /// ⌘R for the section on screen, published by its toolbar refresh.
    public struct RefreshScreenAction {
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
                .frame(width: 400, height: 240)
                .macToolbarRefresh(onRefresh: { try? await Task.sleep(for: .seconds(2)) }, onFinished: {})
        }
    }
#endif
