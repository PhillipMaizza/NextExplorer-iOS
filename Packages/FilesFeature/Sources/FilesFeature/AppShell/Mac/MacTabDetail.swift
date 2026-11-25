#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import SwiftUI

    /// The Mac split view's detail: the selected section. One split view whose detail swaps by
    /// section, so the sidebar and its toggle stay put.
    struct MacTabDetail: View {
        let store: StoreOf<MainTabFeature>
        @State private var inspectorReserve: CGFloat = .zero
        @State private var browseOpener: MacBrowseOpener

        init(store: StoreOf<MainTabFeature>) {
            self.store = store
            _browseOpener = State(initialValue: MacBrowseOpener { store.send(.tabSelected(.browse)) })
        }

        var body: some View {
            if store.selectedTab == .settings {
                section
            } else {
                MacPaneCard(title: nil, subtitle: nil, reserve: inspectorReserve) {
                    section.padding(.horizontal, MacPaneInset.section)
                }
                .overlayPreferenceValue(MacEmptyGuideKey.self) { guide in
                    ZStack {
                        if let guide {
                            MacListGuideView(guide: guide)
                                .transition(.opacity)
                        }
                    }
                    .animation(DSMotion.stateFade, value: guide)
                }
                .environment(\.showMacBrowse, browseOpener)
                .onPreferenceChange(MacInspectorReserveKey.self) { reserve in
                    withAnimation(DSMotion.stateFade) { inspectorReserve = reserve }
                }
            }
        }

        @ViewBuilder
        private var section: some View {
            switch store.selectedTab {
            case .browse:
                BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
            case .favorites:
                FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
            case .shared:
                SharedView(store: store.scope(state: \.shared, action: \.shared))
            case .downloads:
                OfflineTabView(
                    store: store.scope(state: \.downloads, action: \.downloads),
                    offlineStore: store.scope(state: \.offlineManage, action: \.offlineManage),
                    favorites: store.favorites.favorites
                )
            case .settings:
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            case .trash:
                MacTrashView(store: store.scope(state: \.trash, action: \.trash))
            }
        }
    }

    /// What the Mac split view adds over every section: the search panel's opener, the offline bar
    /// beside the sidebar, the transfers button and the window's Upload, Refresh and Search.
    struct MacSplitChrome: ViewModifier {
        let store: StoreOf<MainTabFeature>
        /// Where the sidebar ends, so the offline bar and the toolbar's controls start beside it.
        let sidebarWidth: CGFloat
        var isSidebarCompact = false
        let toggleSidebar: () -> Void

        @State private var topInset: CGFloat = 0
        @State private var isFullScreen = false
        @State private var windowWidth: CGFloat = 0
        @FocusedValue(\.uploadToVisibleFolder) private var upload
        @FocusedValue(\.refreshVisibleScreen) private var refresh
        @FocusedValue(\.sharedSegment) private var sharedSegment
        @FocusedValue(\.openMacInspector) private var openInspector
        @FocusedValue(\.macSearchText) private var searchText
        @FocusedValue(\.closeMacInspector) private var closeInspector

        func body(content: Content) -> some View {
            content
                .modifier(MacOfflineStatusBar(store: store, leadingInset: sidebarWidth))
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
                .overlay(alignment: .top) {
                    if !isFullScreen {
                        topBar
                            .frame(height: topInset)
                            .offset(y: -topInset)
                    }
                }
                .background { MacFullScreenReader(isFullScreen: $isFullScreen) }
                .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { windowWidth = $0 }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if isFullScreen {
                            topBar.frame(width: MacTopBar.fullScreenWidth(window: windowWidth))
                        } else {
                            Color.clear
                                .frame(width: .borderWidthHairline, height: .borderWidthHairline)
                                .accessibilityHidden(true)
                        }
                    }
                    .macPlainToolbarItem()
                }
                .toolbar(removing: .title)
                .toolbarBackground(Color.macChrome, for: .windowToolbar)
                .toolbarBackground(isFullScreen ? .visible : .hidden, for: .windowToolbar)
        }

        private var topBar: some View {
            MacTopBar(
                store: store,
                sidebarWidth: sidebarWidth,
                isFullScreen: isFullScreen,
                isSidebarCompact: isSidebarCompact,
                toggleSidebar: toggleSidebar,
                refresh: sharedSegment == nil ? refresh : nil,
                searchText: searchText,
                actions: MacWindowActions(
                    upload: upload,
                    refresh: nil,
                    isShared: sharedSegment != nil,
                    openInspector: openInspector,
                    closeInspector: closeInspector
                )
            )
        }
    }

    #Preview("Split chrome") {
        NavigationStack {
            Text(verbatim: "Section")
                .frame(width: 600, height: 300)
        }
        .modifier(MacSplitChrome(
            store: Store(initialState: MainTabFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                user: User.preview
            )) { MainTabFeature() },
            sidebarWidth: MacSidebarWidth.ideal,
            toggleSidebar: {}
        ))
    }

    #Preview("Browse") {
        MacTabDetail(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )) { MainTabFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .frame(width: 700, height: 400)
    }
#endif
