#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let lightsInset: CGFloat = 92
        static let fullScreenInset: CGFloat = .zero
        static let fullScreenMargins: CGFloat = .space32
        static let trailingInset: CGFloat = .space16
    }

    private enum TitleBarDoubleClick: String {
        case minimize = "Minimize"
        case nothing = "None"

        static let preferenceKey = "AppleActionOnDoubleClick"

        @MainActor
        static func perform() {
            guard let window = NSApp.keyWindow else { return }
            switch UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) {
            case .minimize: window.miniaturize(nil)
            case .nothing: break
            case nil: window.zoom(nil)
            }
        }
    }

    struct MacTopBar: View {
        let store: StoreOf<MainTabFeature>
        let sidebarWidth: CGFloat
        var isFullScreen = false
        var isSidebarCompact = false
        let toggleSidebar: () -> Void
        var refresh: RefreshScreenAction?
        var searchText: Binding<String>?
        let actions: MacWindowActions

        private var searchPrompt: String {
            if actions.isShared {
                return L10n.Shared.searchPrompt
            }
            return store.selectedTab == .trash ? L10n.Trash.searchPrompt : L10n.Spotlight.placeholder
        }

        var body: some View {
            HStack(spacing: MacToolbarMetrics.gap) {
                HStack(spacing: MacToolbarMetrics.gap) {
                    button(IconKit.macToolbarSidebar, label: L10n.Menu.toggleSidebar, action: toggleSidebar)
                    button(IconKit.macToolbarBack, label: L10n.Common.back) { store.send(.backRequested) }
                        .disabled(!store.canGoBack)
                    button(IconKit.macToolbarForward, label: L10n.Menu.forward) { store.send(.forwardRequested) }
                        .disabled(!store.canGoForward)
                    button(IconKit.macToolbarUp, label: L10n.Menu.enclosingFolder) {
                        store.send(.enclosingFolderRequested)
                    }
                    .disabled(!store.canGoUp)
                    if let refresh {
                        MacRefreshToolbarButton(isRefreshing: refresh.isRefreshing) { refresh() }
                            .transition(MacWindowActions.buttonTransition)
                    }
                }
                .animation(DSMotion.controlMorph, value: refresh != nil)
                .padding(.leading, max(.zero, sidebarWidth - edgeInset))
                .animation(DSMotion.controlMorph, value: isSidebarCompact)
                MacTopBarSearch(
                    text: searchText,
                    prompt: searchPrompt
                ) { store.send(.spotlightOpened) }
                HStack(spacing: MacToolbarMetrics.gap) {
                    if store.downloadQueue.isBarVisible {
                        MacTransferActivityButton(store: store)
                            .buttonStyle(.macToolbarCircle)
                            .macTransferButtonAnchor(.downloads)
                            .transition(MacWindowActions.buttonTransition)
                    }
                    actions
                }
                .animation(DSMotion.controlMorph, value: store.downloadQueue.isBarVisible)
            }
            .padding(.leading, edgeInset)
            .padding(.trailing, Metrics.trailingInset)
            .frame(maxHeight: .infinity)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .simultaneousGesture(TapGesture(count: 2).onEnded { TitleBarDoubleClick.perform() })
            }
            .accessibilityElement(children: .contain)
        }

        static func fullScreenWidth(window: CGFloat) -> CGFloat {
            max(.zero, window - Metrics.fullScreenMargins)
        }

        private var edgeInset: CGFloat {
            isFullScreen ? Metrics.fullScreenInset : Metrics.lightsInset
        }

        private func button(_ icon: Image, label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) { icon.macToolbarGlyph() }
                .buttonStyle(.macToolbarCircle)
                .accessibilityLabelWithTooltip(label)
        }
    }

    #Preview("Top bar") {
        MacTopBar(
            store: Store(initialState: MainTabFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                user: User.preview
            )) { MainTabFeature() },
            sidebarWidth: MacSidebarWidth.ideal,
            toggleSidebar: {},
            refresh: RefreshScreenAction(isRefreshing: false) {},
            searchText: .constant(""),
            actions: MacWindowActions(upload: nil, refresh: nil, isShared: false, openInspector: nil)
        )
        .frame(width: 1400, height: 52)
        .background(Color.macChrome)
    }
#endif
