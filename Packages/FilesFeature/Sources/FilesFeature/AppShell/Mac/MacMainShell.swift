#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacMainShell: View {
        let store: StoreOf<MainTabFeature>
        @AppStorage(AppStorageKeys.macSidebarCompact) private var isSidebarCompact = false
        @AppStorage(AppStorageKeys.macSidebarWidth) private var expandedWidth = Double(MacSidebarWidth.ideal)
        @State private var dragStartWidth: CGFloat?
        @State private var liveWidth: CGFloat?
        @State private var isAccountPanelShown = false
        @State private var isDisplayedCompact: Bool?

        private var isRailShown: Bool {
            isDisplayedCompact ?? isSidebarCompact
        }

        private var sidebarWidth: CGFloat {
            isRailShown ? MacSidebarRail.width : liveWidth ?? expandedWidth
        }

        private var detailInset: CGFloat {
            isSidebarCompact ? MacSidebarRail.width : liveWidth ?? expandedWidth
        }

        var body: some View {
            ZStack(alignment: .leading) {
                MacTabDetail(store: store)
                    .environment(\.isSplitViewDetail, true)
                    .padding(.leading, detailInset)
                MainTabSidebar(store: store)
                    .environment(\.isMacSidebarRail, isRailShown)
                    .environment(\.isMacAccountPanelShown, $isAccountPanelShown)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .macChromeBackground()
                    .overlay(alignment: .trailing) { resizeHandle }
            }
            .macChromeBackground()
            .overlay(alignment: .bottom) {
                SplitDetailBreadcrumb(store: store)
                    .padding(.leading, detailInset)
            }
            .onAppear {
                isDisplayedCompact = isSidebarCompact
            }
            .onChange(of: isSidebarCompact) { _, isCompact in
                isAccountPanelShown = false
                withAnimation(DSMotion.controlMorph) { isDisplayedCompact = isCompact }
            }
            .platformAccentTint()
            .modifier(MacSplitChrome(
                store: store,
                sidebarWidth: sidebarWidth,
                isSidebarCompact: isRailShown,
                toggleSidebar: toggleSidebar
            ))
            .overlay(alignment: .bottomLeading) { accountPanel }
            .overlay {
                if let spotlightStore = store.scope(state: \.spotlight, action: \.spotlight.presented) {
                    SpotlightView(store: spotlightStore)
                }
            }
            .animation(DSMotion.stateFade, value: store.spotlight != nil)
            .focusedSceneValue(\.toggleMacSidebar, ToggleSidebarAction(perform: toggleSidebar))
        }

        private func toggleSidebar() {
            isSidebarCompact.toggle()
        }

        private var accountPanel: some View {
            ZStack(alignment: .bottomLeading) {
                if isAccountPanelShown {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isAccountPanelShown = false }
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    MacAccountPanel(store: store.scope(state: \.settings, action: \.settings)) {
                        isAccountPanelShown = false
                    }
                    .padding(MacAccountPanel.padding(isRail: isRailShown))
                    .transition(.scale(scale: MacSidebarWidth.panelAppearScale, anchor: .bottomLeading)
                        .combined(with: .opacity))
                }
            }
            .animation(DSMotion.pop, value: isAccountPanelShown)
        }

        private var resizeHandle: some View {
            Color.clear
                .frame(width: MacSidebarWidth.handle)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStartWidth ?? sidebarWidth
                            dragStartWidth = start
                            resize(to: start + value.translation.width)
                        }
                        .onEnded { _ in
                            if let liveWidth, !isSidebarCompact {
                                expandedWidth = liveWidth
                            }
                            liveWidth = nil
                            dragStartWidth = nil
                        }
                )
                .accessibilityHidden(true)
        }

        private func resize(to proposed: CGFloat) {
            let collapses = proposed < MacSidebarWidth.collapseThreshold
            if collapses != isSidebarCompact {
                isSidebarCompact = collapses
            }
            if !collapses {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    liveWidth = min(max(proposed, MacSidebarWidth.min), MacSidebarWidth.max)
                }
            }
        }
    }

    public struct ToggleSidebarAction {
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var toggleMacSidebar: ToggleSidebarAction?
    }

    #Preview("Main window") {
        MacMainShell(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )) { MainTabFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
        .frame(width: 1100, height: 700)
    }
#endif
