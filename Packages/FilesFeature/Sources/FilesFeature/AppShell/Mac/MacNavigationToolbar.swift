#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = 18
    }

    struct MacSidebarToolbar: ViewModifier {
        let store: StoreOf<MainTabFeature>
        @Binding var columnVisibility: NavigationSplitViewVisibility

        func body(content: Content) -> some View {
            content
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    if columnVisibility != .detailOnly {
                        MacNavigationToolbar(store: store, columnVisibility: $columnVisibility)
                    }
                }
        }
    }

    struct MacNavigationToolbar: ToolbarContent {
        let store: StoreOf<MainTabFeature>
        @Binding var columnVisibility: NavigationSplitViewVisibility

        var body: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                button(IconKit.macToolbarSidebar, label: L10n.Menu.toggleSidebar) {
                    withAnimation(DSMotion.contentReveal) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .navigation)
            }
            ToolbarItem(placement: .navigation) {
                button(IconKit.macToolbarBack, label: L10n.Common.back) { store.send(.backRequested) }
                    .disabled(!store.canGoBack)
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .navigation)
            }
            ToolbarItem(placement: .navigation) {
                button(IconKit.macToolbarForward, label: L10n.Menu.forward) { store.send(.forwardRequested) }
                    .disabled(!store.canGoForward)
            }
        }

        private func button(_ icon: Image, label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            }
            .accessibilityLabelWithTooltip(label)
        }
    }
#endif
