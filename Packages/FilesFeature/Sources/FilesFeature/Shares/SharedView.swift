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
    /// How often the view re-checks whether an open link has crossed its expiry.
    static let expiryCheckInterval: TimeInterval = 30
}

struct SharedView: View {
    @Bindable var store: StoreOf<SharedFeature>
    @State private var toastMessage: DSToastMessage?
    @State private var isSortSheetPresented = false

    /// Drives both the segmented control and the paged `TabView`. A tap on the control and a
    /// swipe between pages land on the same reducer action; `withAnimation` gives the tap the
    /// same slide the swipe gets for free.
    private var segment: Binding<SharedFeature.Segment> {
        Binding(
            get: { store.segment },
            set: { newValue in withAnimation(DSMotion.disclosure) { _ = store.send(.segmentChanged(newValue)) } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        // No op setter: the sheet is dismiss disabled and only ever closes through one of
        // `DSAlertSheet`'s own buttons, each of which drives the reducer directly. This keeps
        // SwiftUI from firing a stray dismiss action into a torn down presentation.
        Binding(get: { store.deleteConfirmationShare != nil }, set: { _ in })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DSSegmentedControl(
                    options: SharedFeature.Segment.allCases,
                    selection: segment,
                    label: { $0.title }
                )
                .padding(.horizontal, Constants.segmentedControlHorizontalPadding)
                .padding(.top, Constants.segmentedControlTopPadding)
                .padding(.bottom, Constants.segmentedControlBottomPadding)

                #if os(macOS)
                    SharedSegmentList(
                        store: store,
                        segment: store.segment,
                        onToast: { toastMessage = $0 }
                    )
                    .id(store.segment)
                #else
                    TabView(selection: segment) {
                        ForEach(SharedFeature.Segment.allCases, id: \.self) { pageSegment in
                            SharedSegmentList(
                                store: store,
                                segment: pageSegment,
                                onToast: { toastMessage = $0 }
                            )
                            .tag(pageSegment)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
            .backgroundGradient()
            // Title lives in the pinned header (see `PinnedTitleSearchHeader`), which also keeps
            // the search field visible above the paged By-me/With-me lists.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: L10n.Shared.navigationTitle,
                    searchText: $store.searchQuery.sending(\.searchQueryChanged)
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if case let .cached(fetchedAt) = store.dataSources[store.segment] ?? .live {
                    DSInfoCard(L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt)))
                        .padding(.horizontal, .space16)
                        .padding(.vertical, .space8)
                        .background(Color.backgroundPrimary)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.dataSources[store.segment])
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SortToolbarButton(isDisabled: store.isCurrentSegmentEmpty) { isSortSheetPresented = true }
                }
            }
            .sheet(isPresented: $isSortSheetPresented) {
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
            .sheet(item: $store.scope(state: \.editSheet, action: \.editSheet)) { editStore in
                EditShareSheet(store: editStore)
            }
            .sheet(isPresented: deleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.Shared.deleteTitle,
                    message: L10n.Shared.deleteMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteConfirmed) },
                    onDismiss: { store.send(.deleteCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.deleteConfirmationShare != nil)
            .dsToast($toastMessage)
            .task { store.send(.onAppear) }
            .task {
                while !Task.isCancelled {
                    store.send(.expiryTick(Date()))
                    try? await Task.sleep(for: .seconds(Constants.expiryCheckInterval))
                }
            }
            .onChange(of: store.externalRevision) { _, _ in store.send(.externalRevisionChanged) }
            .onChange(of: store.actionErrorMessage) { _, newValue in
                if let newValue {
                    toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue)
                }
            }
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
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
    )
    mutateState(&state)
    var client = FilesClient.previewValue
    configureClient(&client)
    return SharedView(store: Store(initialState: state) { SharedFeature() } withDependencies: {
        $0.filesClient = client
    })
}

#Preview("By me — content") {
    sharedPreview()
}

#Preview("Empty — With me") {
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
