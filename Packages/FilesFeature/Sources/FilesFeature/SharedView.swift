import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI
import UIKit

private enum Constants {
    static let segmentedControlHorizontalPadding: CGFloat = .space16
    static let segmentedControlTopPadding: CGFloat = .space8
    static let segmentedControlBottomPadding: CGFloat = .space12
    /// How often the view re-checks whether an open link has crossed its expiry.
    static let expiryCheckInterval: TimeInterval = 30
    /// Redacted skeleton rows, keyed by the placeholder name length. Uneven so the skeleton
    /// doesn't line up as flat columns.
    static let skeletonNameLengths = [9, 14, 6, 11, 8, 13, 7, 10]
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
            set: { newValue in withAnimation(DSMotion.disclosure) { store.send(.segmentChanged(newValue)) } }
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
            }
            .backgroundGradient()
            .navigationTitle(L10n.Shared.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Common.search
            )
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
                if let newValue { toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue) }
            }
        }
        .tint(Color.accent)
    }
}

/// One page of the Shared tab's paged `TabView` — the grouped list of shares for a single
/// segment, with its own skeleton, empty/error overlay and pull-to-refresh. Reads only its
/// segment's slice of the store so a swipe reveals real content, not the active segment's.
private struct SharedSegmentList: View {
    let store: StoreOf<SharedFeature>
    let segment: SharedFeature.Segment
    let onToast: (DSToastMessage) -> Void

    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull-to-refresh rubber-band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0
    /// Flipped once a pull-to-refresh finishes, purely as a `.hapticFeedback` trigger.
    @State private var didFinishRefreshing = false

    private var phase: DataPhase { store.state.phase(for: segment) }
    private var errorMessage: String? { phase.errorMessage }
    private var isEmpty: Bool { store.state.isEmpty(for: segment) }
    private var activeShares: IdentifiedArrayOf<Share> { store.state.activeShares(for: segment) }
    private var expiredShares: IdentifiedArrayOf<Share> { store.state.expiredShares(for: segment) }

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
        List {
            if listPhase == .loading {
                skeletonRows
            } else {
                section(for: activeShares, header: nil)
                if !expiredShares.isEmpty {
                    section(for: expiredShares, header: L10n.Shared.sectionExpired)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollPullOffset($pullOffset)
        .refreshable {
            await store.send(.refreshRequested).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in errorMessage == nil }
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.state.displayedShares(for: segment))
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
                SharedLinkCard(
                    share: share, serverURL: store.serverURL, isByMe: true, isExpired: false,
                    isDeleting: false, onDelete: {}, onCopied: { _ in }
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
        let lastID = shares.last?.id
        Section {
            ForEach(shares) { share in
                SharedLinkCard(
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
                .listRowSeparator(share.id == firstID ? .hidden : .visible, edges: .top)
                .listRowSeparator(share.id == lastID ? .hidden : .visible, edges: .bottom)
            }
        } header: {
            if let header {
                DSFieldLabel(header)
            }
        }
    }
}

/// One share on the Shared tab: a collapsed header (name + path) that expands to its
/// metadata (shared-with / access / expiration), a direct-link mode picker, then the
/// per-link actions. "With me" shares hide the path and the delete action.
private struct SharedLinkCard: View {
    let share: Share
    let serverURL: URL
    let isByMe: Bool
    let isExpired: Bool
    let audience: SharedFeature.State.Audience
    let sharedByText: String
    let isDeleting: Bool
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onCopied: (String) -> Void

    @State private var isExpanded: Bool
    /// Split from `isExpanded` so the chevron spins first and the body reveal follows a beat
    /// later, rather than both riding one spring.
    @State private var isChevronRotated: Bool
    @State private var directLinkMode: DirectLinkMode = .auto

    init(
        share: Share,
        serverURL: URL,
        isByMe: Bool,
        isExpired: Bool,
        audience: SharedFeature.State.Audience = .anyone,
        sharedByText: String = "",
        isDeleting: Bool,
        startExpanded: Bool = false,
        onDelete: @escaping () -> Void,
        onEdit: @escaping () -> Void = {},
        onCopied: @escaping (String) -> Void
    ) {
        self.share = share
        self.serverURL = serverURL
        self.isByMe = isByMe
        self.isExpired = isExpired
        self.audience = audience
        self.sharedByText = sharedByText
        self.isDeleting = isDeleting
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onCopied = onCopied
        self._isExpanded = State(initialValue: startExpanded)
        self._isChevronRotated = State(initialValue: startExpanded)
    }

    private enum Metrics {
        static let padding: CGFloat = .space16
        /// Matches the Browse file row's vertical rhythm (`FileRowView`).
        static let headerVerticalPadding: CGFloat = .space16
        /// The chevron spin runs first; the body reveal is delayed by this much.
        static let chevronSpinDuration: Double = 0.18
        static var chevronSpin: Animation { .snappy(duration: chevronSpinDuration) }
        static let actionRowSpacing: CGFloat = .space8
        /// One value for both the meta rows and the link-mode row so they read as one list.
        static let rowVerticalPadding: CGFloat = .space8
        static let actionVerticalPadding: CGFloat = .space12
        static let iconSize: CGFloat = .iconMedium
        static let metaIconSize: CGFloat = .iconSmall
        static let chevronSize: CGFloat = .iconXSmall
        static let actionIconSize: CGFloat = .iconSmall
        static let badgeHorizontalPadding: CGFloat = .space8
        static let badgeVerticalPadding: CGFloat = .space2
        /// Chip tint strength — the recipient's categorical color at low alpha behind its name.
        static let chipFillOpacity: Double = 0.16
        static let deletingOpacity: Double = 0.4
        /// Expired links mute the info rows — but never the actions, which stay usable
        /// (delete) or at least fully legible.
        static let expiredInfoOpacity: Double = 0.55
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Group {
                    if isByMe { ownerBody } else { recipientBody }
                }
                .transition(.opacity)
            }
        }
        .opacity(isDeleting ? Metrics.deletingOpacity : 1)
        .disabled(isDeleting)
    }

    private var accessIcon: Image {
        share.accessMode == .readonly ? IconKit.lock : IconKit.lockOpen
    }

    /// "By me": full metadata + the direct-link mode picker + copy/delete actions. Web keeps
    /// expired shares fully usable for the owner (the link just stops working server-side),
    /// so nothing here dims or disables on expiry — the header badge is the only signal.
    private var ownerBody: some View {
        VStack(alignment: .leading, spacing: .space8) {
            sharedWithRow
            metaRow(accessIcon, L10n.Shared.metaAccess, share.accessMode.title)
            metaRow(IconKit.calendar, L10n.Shared.metaExpiration, expiresText, isWarning: isExpired)
            linkModeRow

            HStack(spacing: Metrics.actionRowSpacing) {
                pillAction(IconKit.link, L10n.Shared.actionShareLink, tint: .accent, isEnabled: true) {
                    copy(shareLinkString, label: L10n.Shared.copiedShareLink)
                }
                pillAction(
                    IconKit.copy,
                    share.isDirectory ? L10n.Shared.actionFolderLink : L10n.Shared.actionFileLink,
                    tint: .accent,
                    isEnabled: true
                ) {
                    copy(directLinkString, label: share.isDirectory ? L10n.Shared.copiedFolderZip : L10n.Shared.copiedDirectFile)
                }
            }

            HStack(spacing: Metrics.actionRowSpacing) {
                pillAction(IconKit.rename, L10n.Common.edit, tint: .accent, isEnabled: true, action: onEdit)
                pillAction(IconKit.delete, L10n.Common.delete, tint: .negative, isEnabled: true, action: onDelete)
            }
            .padding(.top, Metrics.actionRowSpacing)
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, Metrics.padding)
    }

    /// "With me": read-only — no link, no mode picker, no delete, matching the web
    /// `SharedWithMeView`. Just who shared it, the access level, and the expiry.
    private var recipientBody: some View {
        VStack(alignment: .leading, spacing: .space8) {
            metaRow(IconKit.person, L10n.Shared.metaSharedBy, sharedByText)
            metaRow(accessIcon, L10n.Shared.metaAccess, share.accessMode.title)
            metaRow(IconKit.calendar, L10n.Shared.metaExpiration, expiresText, isWarning: isExpired)
        }
        .opacity(isExpired ? Metrics.expiredInfoOpacity : 1)
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, Metrics.padding)
    }

    /// "Shared with" — a globe + label for `anyone`; for specific users, the label row plus a
    /// full-width wrapping strip showing every recipient as its own colored chip (a `+N` chip
    /// covers any recipients whose name hasn't resolved yet).
    @ViewBuilder
    private var sharedWithRow: some View {
        VStack(alignment: .leading, spacing: .space8) {
            HStack(alignment: .top, spacing: .space8) {
                (audienceIsAnyone ? IconKit.web : IconKit.people)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
                    .padding(.top, .space2)
                Text(L10n.Shared.metaSharedWith).type(.body2(.regular), style: .primary(for: .label))
                Spacer(minLength: .space8)
                if audienceIsAnyone {
                    Text(L10n.Shared.anyoneWithLink).type(.body2(.regular), style: .secondary)
                }
            }
            if case let .users(names, unnamed) = audience {
                recipientChips(names: names, unnamed: unnamed)
            }
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Every recipient as its own chip, each in a stable per-name color, wrapping onto as many
    /// rows as it takes. Any recipients whose display name hasn't loaded collapse into a
    /// trailing neutral `+N`.
    @ViewBuilder
    private func recipientChips(names: [String], unnamed: Int) -> some View {
        DSFlowLayout(horizontalSpacing: .space4, verticalSpacing: .space4) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .type(.caption(.semibold))
                    .foregroundStyle(Color.categorical(for: name))
                    .lineLimit(1)
                    .padding(.horizontal, .space8)
                    .padding(.vertical, Metrics.badgeVerticalPadding)
                    .background(Capsule().fill(Color.categorical(for: name).opacity(Metrics.chipFillOpacity)))
            }
            if unnamed > 0 {
                Text(L10n.Shared.moreRecipients(unnamed))
                    .type(.caption(.semibold), style: .secondary)
                    .padding(.horizontal, .space8)
                    .padding(.vertical, Metrics.badgeVerticalPadding)
                    .background(Capsule().fill(Color.secondaryDS.opacity(Metrics.chipFillOpacity)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audienceIsAnyone: Bool {
        if case .anyone = audience { return true }
        return false
    }

    /// Folder glyph for directory shares, a real thumbnail for a by-me image share, otherwise
    /// a per-format `FileTypeIcon` keyed off the shared item's own extension — same treatment
    /// the Browse list gives a file row.
    @ViewBuilder
    private var shareIcon: some View {
        if share.isDirectory {
            IconKit.folderFill
                .resizable().scaledToFit()
                .foregroundStyle(Color.accent)
        } else if let thumbnailPath {
            ThumbnailImage(
                serverURL: serverURL,
                path: thumbnailPath,
                signature: "\(share.updatedAt.timeIntervalSince1970)",
                fallbackIcon: IconKit.document,
                iconTint: Color.secondaryDS
            )
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        } else {
            FileTypeIcon(kind: (share.displayName as NSString).pathExtension)
        }
    }

    /// Full server path for a by-me image share — the only case a real thumbnail is
    /// reachable: shared-with-me links carry only the leaf name, and non-image kinds have no
    /// server thumbnail to fetch.
    private var thumbnailPath: String? {
        guard isByMe, let path = share.sourcePath, !path.isEmpty else { return nil }
        let ext = (share.displayName as NSString).pathExtension
        guard FileItem.isImageKind(ext) || FileItem.isRawImageKind(ext) else { return nil }
        return path
    }

    private var header: some View {
        Button {
            withAnimation(Metrics.chevronSpin) { isChevronRotated.toggle() }
            withAnimation(DSMotion.disclosure.delay(Metrics.chevronSpinDuration)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: .space12) {
                shareIcon
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)

                VStack(alignment: .leading, spacing: .space2) {
                    HStack(spacing: .space8) {
                        Text(share.displayName)
                            .type(.body2(.semibold), style: .primary(for: .label))
                            .lineLimit(1)
                        if isExpired {
                            Text(L10n.Shared.badgeExpired.uppercased())
                                .type(.caption(.semibold), style: .error)
                                .padding(.horizontal, Metrics.badgeHorizontalPadding)
                                .padding(.vertical, Metrics.badgeVerticalPadding)
                                .background(RoundedRectangle(cornerRadius: .radiusXSmall).fill(Color.negative.opacity(0.15)))
                        }
                    }
                    if isByMe, let path = share.sourcePath, !path.isEmpty {
                        Text(path)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                // Points down when collapsed, flips up when expanded.
                IconKit.chevronDown
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                    .rotationEffect(.degrees(isChevronRotated ? 180 : 0))
            }
            .padding(.horizontal, Metrics.padding)
            .padding(.vertical, Metrics.headerVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
    }

    private var linkModeRow: some View {
        HStack(spacing: .space8) {
            IconKit.shareLink
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(L10n.Shared.linkMode).type(.body2(.regular), style: .primary(for: .label))
            Spacer()
            Picker(L10n.Shared.linkMode, selection: $directLinkMode) {
                ForEach(DirectLinkMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.secondaryDS)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Same font/padding as `linkModeRow` so the whole expanded block reads as one list.
    private func metaRow(_ icon: Image, _ label: String, _ value: String, isWarning: Bool = false) -> some View {
        HStack(spacing: .space8) {
            icon
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(label).type(.body2(.regular), style: .primary(for: .label))
            Spacer()
            Text(value)
                .type(.body2(.regular), style: isWarning ? .error : .secondary)
                .multilineTextAlignment(.trailing)
                .truncationMode(.tail)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Filled pill for the copy/delete actions. `tint` is `.accent` or `.negative`. Stays
    /// full opacity even when disabled (an expired link's copy buttons) — it just stops
    /// responding; `copy()` guards the action too.
    private func pillAction(_ icon: Image, _ title: String, tint: Color, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: .space8) {
                icon
                    .resizable().scaledToFit()
                    .frame(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
                Text(title).type(.body3(.semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.actionVerticalPadding)
            .background(RoundedRectangle(cornerRadius: .radiusControl).fill(tint.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .allowsHitTesting(isEnabled)
    }

    private var expiresText: String {
        guard let expiresAt = share.expiresAt else { return L10n.Common.never }
        return Self.expiryFormatter.string(from: expiresAt)
    }

    private var baseURLString: String {
        if let scheme = serverURL.scheme, let host = serverURL.host {
            let port = serverURL.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        return serverURL.absoluteString
    }

    private var shareLinkString: String {
        "\(baseURLString)/share/\(share.shareToken)"
    }

    private var directLinkString: String {
        let base = "\(baseURLString)/api/share/\(share.shareToken)/file"
        return directLinkMode == .auto ? base : "\(base)?mode=\(directLinkMode.rawValue)"
    }

    private func copy(_ string: String, label: String) {
        UIPasteboard.general.string = string
        onCopied(label)
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    SharedView(
        store: Store(
            initialState: SharedFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}

#Preview("Empty — With me") {
    SharedView(
        store: Store(
            initialState: SharedFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
            $0.filesClient.sharedWithMeLinks = { _ in [] }
        }
    )
}

private extension Share {
    static func previewCard(
        isDirectory: Bool = false,
        target: ShareTarget = .anyone,
        hasPassword: Bool = false,
        expiresAt: Date? = nil,
        sourcePath: String? = "Documents/Bills/Electricity"
    ) -> Share {
        Share(
            id: UUID().uuidString, shareToken: "UrkLIGIHMF", ownerId: "me",
            sourcePath: sourcePath, sourceName: sourcePath == nil ? "Team Roadmap" : nil,
            isDirectory: isDirectory, accessMode: .readonly, sharingType: target,
            hasPassword: hasPassword, expiresAt: expiresAt, label: sourcePath == nil ? "Team Roadmap" : "Electricity",
            createdAt: Date(), updatedAt: Date()
        )
    }
}

#Preview("Card — collapsed / expanded") {
    let url = URL(string: "https://cloud.phillipmaizza.com")!
    return ScrollView {
        VStack(spacing: .space12) {
            SharedLinkCard(share: .previewCard(isDirectory: true), serverURL: url, isByMe: true, isExpired: false, isDeleting: false, onDelete: {}, onCopied: { _ in })
            SharedLinkCard(share: .previewCard(), serverURL: url, isByMe: true, isExpired: false, isDeleting: false, startExpanded: true, onDelete: {}, onCopied: { _ in })
        }
        .padding(.space16)
    }
    .background(Color.backgroundPrimary)
}

#Preview("Card — users / password / expiry") {
    let url = URL(string: "https://cloud.phillipmaizza.com")!
    return ScrollView {
        VStack(spacing: .space12) {
            SharedLinkCard(share: .previewCard(target: .users, hasPassword: true), serverURL: url, isByMe: true, isExpired: false, audience: .users(names: ["Jamie Rivera", "Sam Okafor", "Jeremy Brown", "Dana Lee"], unnamed: 1), isDeleting: false, startExpanded: true, onDelete: {}, onCopied: { _ in })
            SharedLinkCard(share: .previewCard(expiresAt: Date().addingTimeInterval(86_400 * 3)), serverURL: url, isByMe: true, isExpired: false, isDeleting: false, startExpanded: true, onDelete: {}, onCopied: { _ in })
        }
        .padding(.space16)
    }
    .background(Color.backgroundPrimary)
}

#Preview("Card — expired / with me") {
    let url = URL(string: "https://cloud.phillipmaizza.com")!
    return ScrollView {
        VStack(spacing: .space12) {
            SharedLinkCard(share: .previewCard(expiresAt: Date().addingTimeInterval(-3600)), serverURL: url, isByMe: true, isExpired: true, isDeleting: false, startExpanded: true, onDelete: {}, onCopied: { _ in })
            SharedLinkCard(share: .previewCard(sourcePath: nil), serverURL: url, isByMe: false, isExpired: false, isDeleting: false, startExpanded: true, onDelete: {}, onCopied: { _ in })
        }
        .padding(.space16)
    }
    .background(Color.backgroundPrimary)
}
