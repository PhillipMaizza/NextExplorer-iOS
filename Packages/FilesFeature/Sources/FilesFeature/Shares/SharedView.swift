import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let segmentedControlHorizontalPadding: CGFloat = .space16
    static let segmentedControlTopPadding: CGFloat = .space8
    static let segmentedControlBottomPadding: CGFloat = .space12
    /// How often the view rechecks whether an open link has crossed its expiry.
    static let expiryCheckInterval: TimeInterval = 30
}

struct SharedView: View {
    @Bindable var store: StoreOf<SharedFeature>
    @State private var toastMessage: DSToastMessage?
    @State private var isSortSheetPresented = false

    /// Drives both the segmented control and the paged `TabView`. A tap on the control and a
    /// swipe between pages land on the same reducer action; `withAnimation` gives the tap the
    /// same slide the swipe gets for free. The Mac swaps tables instead, with no animation, so the
    /// new table never lays out mid transition.
    private var segment: Binding<SharedFeature.Segment> {
        Binding(
            get: { store.segment },
            set: { newValue in
                #if os(iOS)
                    withAnimation(DSMotion.disclosure) { _ = store.send(.segmentChanged(newValue)) }
                #elseif os(macOS)
                    withTransaction(\.disablesAnimations, true) { _ = store.send(.segmentChanged(newValue)) }
                #endif
            }
        )
    }

    /// The item sheet. Only the reducer closes it: a swipe down arrives here as `nil`.
    private var detailBinding: Binding<SharedFeature.Detail?> {
        Binding(
            get: { store.detail },
            set: { newValue in
                if newValue == nil, store.detail != nil {
                    store.send(.detailDismissed)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The Mac picks the segment in its pane header instead.
                #if os(iOS)
                    DSSegmentedControl(
                        options: SharedFeature.Segment.allCases,
                        selection: segment,
                        label: { $0.title }
                    )
                    .padding(.horizontal, Constants.segmentedControlHorizontalPadding)
                    .padding(.top, Constants.segmentedControlTopPadding)
                    .padding(.bottom, Constants.segmentedControlBottomPadding)
                #endif

                #if os(macOS)
                    MacSharedContent(store: store, onToast: { toastMessage = $0 }) {
                        MacPaneHeader(
                            title: L10n.Shared.navigationTitle,
                            inset: MacPaneInset.sectionHeader,
                            bottom: MacPaneInset.listGap
                        ) {
                            MacSegmentedPicker(
                                L10n.Shared.navigationTitle,
                                options: SharedFeature.Segment.allCases,
                                selection: segment,
                                label: { $0.title }
                            )
                        }
                    }
                #else
                    TabView(selection: segment) {
                        ForEach(SharedFeature.Segment.allCases, id: \.self) { pageSegment in
                            SharedSegmentList(store: store, segment: pageSegment)
                                .tag(pageSegment)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
            .backgroundGradient()
            // Title lives in the pinned header (see `PinnedTitleSearchHeader`), which also keeps
            // the search field visible above the paged By me/With me lists.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS)
                .safeAreaInset(edge: .top, spacing: 0) {
                    PinnedTitleSearchHeader(
                        title: L10n.Shared.navigationTitle,
                        searchText: $store.searchQuery.sending(\.searchQueryChanged)
                    )
                }
            #elseif os(macOS)
                .focusedSceneValue(\.macSearchText, $store.searchQuery.sending(\.searchQueryChanged))
            #endif
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if case let .cached(fetchedAt) = store.dataSources[store.segment] ?? .live {
                        DSInfoCard(L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt)))
                            .padding(.horizontal, .space16)
                            .padding(.vertical, .space8)
                            .background(Color.backgroundPrimary, ignoresSafeAreaEdges: .bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DSMotion.stateFade, value: store.dataSources[store.segment])
                .prefersToolbarItemsInVerticalBar()
            // The Mac table sorts from its column headers instead.
            #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .sortControl) {
                        SortToolbarButton(isDisabled: store.isCurrentSegmentEmpty) { isSortSheetPresented = true }
                    }
                }
            #elseif os(macOS)
                .focusedSceneValue(\.sharedSegment, segment)
            #endif
                .dsSheet(isPresented: $isSortSheetPresented) {
                    SortSheet(
                        options: SharedFeature.SortOption.allCases,
                        directions: BrowseFeature.SortDirection.allCases,
                        sortOption: store.sortOption,
                        sortDirection: store.sortDirection,
                        optionIcon: { $0.icon },
                        optionTitle: { $0.title },
                        directionIcon: { $0.icon },
                        directionTitle: { $0.title },
                        onSelectOption: { store.send(.sortOptionChanged($0)) },
                        onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                        onDismiss: { isSortSheetPresented = false }
                    )
                }
            #if os(macOS)
                .modifier(SharedActionPresentations(store: store, toast: $toastMessage))
            #else
                .sheet(item: detailBinding) { detail in
                    SharedDetailSheet(store: store, presented: detail)
                }
                .sharedActionToast(store: store, toast: $toastMessage, isActive: store.detail == nil)
            #endif
                .dsToast($toastMessage)
                .task { store.send(.onAppear) }
                .task {
                    while !Task.isCancelled {
                        store.send(.expiryTick(Date()))
                        try? await Task.sleep(for: .seconds(Constants.expiryCheckInterval))
                    }
                }
                .onChange(of: store.externalRevision) { _, _ in store.send(.externalRevisionChanged) }
        }
        .tint(Color.accent)
    }
}

@MainActor
private func sharedPreview(
    configureClient: (inout FilesClient) -> Void = { _ in },
    mutateState: (inout SharedFeature.State) -> Void = { _ in }
) -> some View {
    var state = SharedFeature.State(
        serverURL: sharedPreviewServerURL
    )
    mutateState(&state)
    var client = FilesClient.previewValue
    configureClient(&client)
    return SharedView(store: Store(initialState: state) { SharedFeature() } withDependencies: {
        $0.filesClient = client
    })
}

#Preview("By me: content") {
    sharedPreview()
}

#Preview("Empty: With me") {
    sharedPreview(configureClient: { $0.sharedWithMeLinks = { _ in [] } })
}

#Preview("Loading") {
    sharedPreview(mutateState: { $0.phases[.byMe] = .loading })
}

#Preview("Error") {
    sharedPreview(mutateState: {
        $0.phases[.byMe] = .failed(L10n.EmptyState.loadFailed)
    })
}
