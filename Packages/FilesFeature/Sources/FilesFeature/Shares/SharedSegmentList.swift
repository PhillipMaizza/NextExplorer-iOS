import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// One page of the Shared tab's paged `TabView`: the people row and the list of shared items
/// for a single segment, with its own skeleton, empty or error overlay and pull to refresh. Reads
/// only its segment's slice of the store so a swipe reveals real content, not the active segment's.
struct SharedSegmentList: View {
    let store: StoreOf<SharedFeature>
    let segment: SharedFeature.Segment

    private enum Constants {
        /// Redacted skeleton rows, keyed by the placeholder name length. Uneven so the skeleton
        /// doesn't line up as flat columns.
        static let skeletonNameLengths = [9, 14, 6, 11, 8, 13, 7, 10]
    }

    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull to refresh rubber band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0

    private var phase: DataPhase {
        store.state.phase(for: segment)
    }

    private var errorMessage: String? {
        phase.errorMessage
    }

    private var isEmpty: Bool {
        store.state.isEmpty(for: segment)
    }

    /// The card skeleton until this segment has been fetched once, then error / empty /
    /// no results / list.
    private var listPhase: ListPhase {
        .derive(
            hasError: errorMessage != nil,
            hasLoaded: phase.hasLoaded,
            isEmpty: isEmpty,
            hasNoResults: store.state.isSearchWithoutResults(for: segment)
        )
    }

    /// The people row rides the list's scroll offset from above the first row instead of being
    /// a row itself, so it scrolls with the items yet runs edge to edge past the inset cards.
    @State private var scrollOffset: CGFloat = 0
    @State private var railHeight: CGFloat = 0

    private var isRailShown: Bool {
        listPhase != .loading && store.state.isFilterRowVisible(for: segment)
    }

    var body: some View {
        let showsRail = isRailShown
        list(showsRail: showsRail)
            .overlay(alignment: .top) {
                if showsRail {
                    SharedScrollFollower(offset: $scrollOffset) {
                        rail.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { railHeight = $0 }
                    }
                }
            }
            .clipped()
    }

    private func list(showsRail: Bool) -> some View {
        let items = store.state.items(for: segment)
        return DSGroupedList {
            if listPhase == .loading {
                skeletonRows
            } else {
                section(for: items.filter { !$0.isExpired }, header: nil)
                let expired = items.filter(\.isExpired)
                if !expired.isEmpty {
                    section(for: expired, header: L10n.Shared.sectionExpired)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, (showsRail ? railHeight : 0) + .space4, for: .scrollContent)
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        .syncRefreshFeedback(errorMessage: errorMessage, signalsErrorHaptic: false) {
            await store.send(.refreshRequested).finish()
        }
        .overlay {
            ListStateOverlay(
                phase: listPhase,
                errorMessage: errorMessage,
                emptyIcon: IconKit.shareLink,
                emptyMessage: store.state.emptyMessage(for: segment),
                noResultsMessage: L10n.Shared.noSearchMatches(store.searchQuery),
                pullOffset: pullOffset,
                onRetry: { store.send(.refreshRequested) }
            )
            .animation(DSMotion.contentReveal, value: listPhase)
        }
    }

    /// Redacted stand ins that sit in the same grouped `List` as the real rows (and the Mac
    /// table's skeleton rows). Shine suppressed under Reduce Motion.
    static let placeholderShares: [Share] = Constants.skeletonNameLengths.enumerated().map { index, length in
        Share(
            id: "skeleton/\(index)", shareToken: "MMMMMMMMMM", ownerId: "skeleton",
            sourcePath: String(repeating: "M", count: length), isDirectory: index.isMultiple(of: 2),
            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            createdAt: .distantPast, updatedAt: .distantPast
        )
    }

    private var skeletonRows: some View {
        Section {
            ForEach(Array(Self.placeholderItems.enumerated()), id: \.element.id) { index, item in
                SharedItemRow(
                    item: item,
                    serverURL: store.serverURL,
                    isByMe: segment == .byMe,
                    isDeleting: false,
                    onTap: {}
                )
                .redacted(reason: .placeholder)
                .shimmering()
                .allowsHitTesting(false)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(index == Self.placeholderItems.count - 1 ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    static let placeholderItems: [SharedFeature.Item] = placeholderShares.map { share in
        SharedFeature.Item(
            id: share.id,
            name: share.displayName,
            location: share.displayName,
            shares: [share],
            badges: [SharedFeature.ShareBadge(
                id: share.id,
                isAnyone: true,
                people: [],
                unnamedCount: 0,
                expiry: nil
            )],
            isExpired: false
        )
    }

    private var rail: some View {
        SharedPeopleRail(
            options: store.state.filterOptions(for: segment),
            selection: store.state.filter(for: segment),
            onSelect: { filter in
                withAnimation(DSMotion.listDiff) { _ = store.send(.filterChanged(segment, filter)) }
            }
        )
        .padding(.top, .space4)
        .padding(.bottom, .space24)
    }

    private func section(for items: [SharedFeature.Item], header: String?) -> some View {
        let firstID = items.first?.id
        return Section {
            // The row draws its own divider on top of every item but the first.
            ForEach(items) { item in
                SharedItemRow(
                    item: item,
                    serverURL: store.serverURL,
                    isByMe: segment == .byMe,
                    isDeleting: item.shares.allSatisfy { store.deletingIDs.contains($0.id) },
                    showsDivider: item.id != firstID,
                    onTap: { store.send(.detailOpened(segment, item.id)) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(.hidden)
            }
        } header: {
            if let header {
                DSFieldLabel(header)
            }
        }
    }
}

@MainActor
private func segmentListPreview(
    _ mutate: (inout SharedFeature.State) -> Void
) -> some View {
    var state = SharedFeature.State(
        serverURL: sharedPreviewServerURL
    )
    state.now = Date()
    state.userNames = Dictionary(uniqueKeysWithValues: Share.previewShareableUsers.map { (
        $0.id,
        $0.displayName ?? $0.username
    ) })
    mutate(&state)
    let store = Store(initialState: state) { SharedFeature() } withDependencies: {
        $0.filesClient = .previewValue
    }
    return SharedSegmentList(store: store, segment: .byMe)
        .backgroundGradient()
}

/// Shifts its content up by the list's scroll offset. The offset is read here, not in the list's
/// body, so scrolling redraws only the people row instead of rebuilding every item each frame.
private struct SharedScrollFollower<Content: View>: View {
    @Binding var offset: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(y: -offset)
    }
}

#Preview("Segment: content") {
    segmentListPreview {
        $0.byMe = IdentifiedArray(uniqueElements: Share.previewSharedByMe)
        $0.phases[.byMe] = .loaded
    }
}

#Preview("Segment: filtered to a person") {
    segmentListPreview {
        $0.byMe = IdentifiedArray(uniqueElements: Share.previewSharedByMe)
        $0.phases[.byMe] = .loaded
        $0.filters[.byMe] = .people(["u6"])
    }
}

#Preview("Segment: loading") {
    segmentListPreview { $0.phases[.byMe] = .loading }
}

#Preview("Segment: empty") {
    segmentListPreview { $0.phases[.byMe] = .loaded }
}

#Preview("Segment: error") {
    segmentListPreview { $0.phases[.byMe] = .failed(L10n.EmptyState.loadFailed) }
}

#Preview("Segment: no search results") {
    segmentListPreview {
        $0.byMe = IdentifiedArray(uniqueElements: Share.previewSharedByMe)
        $0.phases[.byMe] = .loaded
        $0.searchQuery = "zzzznomatch"
    }
}
