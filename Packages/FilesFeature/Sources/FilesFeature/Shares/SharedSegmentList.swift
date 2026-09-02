import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// One page of the Shared tab's paged `TabView` — the grouped list of shares for a single
/// segment, with its own skeleton, empty/error overlay and pull-to-refresh. Reads only its
/// segment's slice of the store so a swipe reveals real content, not the active segment's.
struct SharedSegmentList: View {
    let store: StoreOf<SharedFeature>
    let segment: SharedFeature.Segment
    let onToast: (DSToastMessage) -> Void

    private enum Constants {
        /// Redacted skeleton rows, keyed by the placeholder name length. Uneven so the skeleton
        /// doesn't line up as flat columns.
        static let skeletonNameLengths = [9, 14, 6, 11, 8, 13, 7, 10]
    }

    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull-to-refresh rubber-band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0
    /// Flipped once a pull-to-refresh finishes, purely as a `.hapticFeedback` trigger.
    @State private var didFinishRefreshing = false
    /// Which shares are expanded. Kept here (not in the row) so the header and its detail can be
    /// two separate list rows: the header row's height never changes, so it can never be
    /// vertically centered by its cell and stays fixed while the detail row animates in/out.
    @State private var expandedIDs: Set<Share.ID> = []

    private var phase: DataPhase { store.state.phase(for: segment) }
    private var errorMessage: String? { phase.errorMessage }
    private var isEmpty: Bool { store.state.isEmpty(for: segment) }

    /// The card skeleton until this segment has been fetched once, then error / empty /
    /// no-results / list.
    private var listPhase: ListPhase {
        if errorMessage != nil { return .error }
        if !phase.hasLoaded && isEmpty { return .loading }
        if isEmpty { return .empty }
        if store.state.isSearchWithoutResults(for: segment) { return .noResults }
        return .content
    }

    var body: some View {
        // One filter+sort pass shared by both sections and the diff animation, rather than
        // three independent derivations (each ran the localized sort) per render.
        let partition = store.state.displayedSharesPartition(for: segment)
        return List {
            if listPhase == .loading {
                skeletonRows
            } else {
                section(for: partition.active, header: nil)
                if !partition.expired.isEmpty {
                    section(for: partition.expired, header: L10n.Shared.sectionExpired)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        .refreshable {
            await store.send(.refreshRequested).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in errorMessage == nil }
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: partition.all)
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
        }
        .animation(DSMotion.contentReveal, value: listPhase)
    }

    /// Redacted collapsed `SharedLinkCard` stand-ins that sit in the *same* grouped `List` as
    /// the real rows. Shine suppressed under Reduce Motion.
    private static let placeholderShares: [Share] = Constants.skeletonNameLengths.enumerated().map { index, length in
        Share(
            id: "skeleton/\(index)", shareToken: "MMMMMMMMMM", ownerId: "skeleton",
            sourcePath: String(repeating: "M", count: length), isDirectory: index.isMultiple(of: 2),
            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            createdAt: .distantPast, updatedAt: .distantPast
        )
    }

    @ViewBuilder
    private var skeletonRows: some View {
        Section {
            ForEach(Array(Self.placeholderShares.enumerated()), id: \.element.id) { index, share in
                SharedLinkHeaderRow(
                    share: share, serverURL: store.serverURL, isByMe: true, isExpired: false,
                    isDeleting: false, isExpanded: false, onToggle: {}
                )
                .redacted(reason: .placeholder)
                .shimmering()
                .allowsHitTesting(false)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(index == Self.placeholderShares.count - 1 ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    @ViewBuilder
    private func section(for shares: IdentifiedArrayOf<Share>, header: String?) -> some View {
        let firstID = shares.first?.id
        Section {
            // Each share is a header row plus, when expanded, a separate detail row. The single
            // separator between shares is drawn on the top of every header but the first; the
            // header/detail pair carries none, so it reads as one card.
            ForEach(shares) { share in
                SharedLinkHeaderRow(
                    share: share,
                    serverURL: store.serverURL,
                    isByMe: segment == .byMe,
                    isExpired: store.state.isExpired(share),
                    isDeleting: store.deletingIDs.contains(share.id),
                    isExpanded: expandedIDs.contains(share.id),
                    onToggle: { toggleExpanded(share.id) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(share.id == firstID ? .hidden : .visible, edges: .top)
                .listRowSeparator(.hidden, edges: .bottom)

                if expandedIDs.contains(share.id) {
                    SharedLinkDetailRow(
                        share: share,
                        serverURL: store.serverURL,
                        isByMe: segment == .byMe,
                        isExpired: store.state.isExpired(share),
                        audience: store.state.audience(for: share),
                        sharedByText: store.state.sharedByLabel(for: share),
                        isDeleting: store.deletingIDs.contains(share.id),
                        onDelete: { store.send(.deleteTapped(share)) },
                        onEdit: { store.send(.editTapped(share)) },
                        onCopied: { onToast(.success($0)) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.backgroundSecondary)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            if let header {
                DSFieldLabel(header)
            }
        }
    }

    private func toggleExpanded(_ id: Share.ID) {
        withAnimation(SharedLinkMetrics.expand) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }
}

@MainActor
private func segmentListPreview(
    _ mutate: (inout SharedFeature.State) -> Void
) -> some View {
    var state = SharedFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
    )
    mutate(&state)
    let store = Store(initialState: state) { SharedFeature() } withDependencies: {
        $0.filesClient = .previewValue
    }
    return SharedSegmentList(store: store, segment: .byMe, onToast: { _ in })
        .backgroundGradient()
}

private let previewByMeShares: [Share] = [
    .previewCard(isDirectory: true),
    .previewCard(target: .users, sourcePath: "Documents/Team/Roadmap"),
    .previewCard(expiresAt: Date().addingTimeInterval(-3600)),
]

#Preview("Segment — content") {
    segmentListPreview {
        $0.byMe = IdentifiedArray(uniqueElements: previewByMeShares)
        $0.phases[.byMe] = .loaded
    }
}

#Preview("Segment — loading") {
    segmentListPreview { $0.phases[.byMe] = .loading }
}

#Preview("Segment — empty") {
    segmentListPreview { $0.phases[.byMe] = .loaded }
}

#Preview("Segment — error") {
    segmentListPreview { $0.phases[.byMe] = .failed(L10n.EmptyState.loadFailed) }
}

#Preview("Segment — no search results") {
    segmentListPreview {
        $0.byMe = IdentifiedArray(uniqueElements: previewByMeShares)
        $0.phases[.byMe] = .loaded
        $0.searchQuery = "zzzznomatch"
    }
}
