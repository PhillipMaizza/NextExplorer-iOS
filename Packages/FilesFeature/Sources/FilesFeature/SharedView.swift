import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import UIKit

private enum Constants {
    static let segmentedControlHorizontalPadding: CGFloat = .space16
    static let segmentedControlTopPadding: CGFloat = .space8
    static let segmentedControlBottomPadding: CGFloat = .space12
    static let cardListInset: CGFloat = .space16
    static let cardListSpacing: CGFloat = .space12
    static let overlayCrossfadeDuration: Double = 0.2
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    /// How often the view re-checks whether an open link has crossed its expiry.
    static let expiryCheckInterval: TimeInterval = 30
}

struct SharedView: View {
    @Bindable var store: StoreOf<SharedFeature>
    @State private var toastMessage: DSToastMessage?
    @State private var isSortSheetPresented = false
    /// Flipped once a pull-to-refresh finishes, purely as a `.hapticFeedback` trigger.
    @State private var didFinishRefreshing = false

    private var segment: Binding<SharedFeature.Segment> {
        Binding(
            get: { store.segment },
            set: { store.send(.segmentChanged($0)) }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.deleteConfirmationShare != nil },
            set: { if !$0 { store.send(.deleteCancelled) } }
        )
    }

    private enum OverlayState: Hashable {
        case none, loading, error, empty, noResults
    }

    private var overlayState: OverlayState {
        if store.isLoading && store.isCurrentSegmentEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if store.isCurrentSegmentEmpty {
            .empty
        } else if store.isSearchWithoutResults {
            .noResults
        } else {
            .none
        }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: Constants.expiryCheckInterval)) { context in
                shareList
                    .task(id: context.date) { store.send(.expiryTick(context.date)) }
            }
            .navigationTitle("Shared")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSortSheetPresented = true
                    } label: {
                        Label { Text("Sort") } icon: { IconKit.sort.foregroundStyle(Color.accent) }
                    }
                    .tint(.accent)
                    .buttonStyle(DSHapticButtonStyle())
                    .disabled(store.isCurrentSegmentEmpty)
                }
            }
            .overlay {
                Group {
                    switch overlayState {
                    case .loading:
                        ProgressView().transition(.opacity)
                    case .error:
                        if let errorMessage = store.errorMessage {
                            EmptyStateView(icon: IconKit.warning, message: errorMessage).transition(.opacity)
                        }
                    case .empty:
                        EmptyStateView(icon: IconKit.shareLink, message: emptyMessage).transition(.opacity)
                    case .noResults:
                        EmptyStateView(icon: IconKit.search, message: "No shares match \u{201C}\(store.searchQuery)\u{201D}.").transition(.opacity)
                    case .none:
                        EmptyView()
                    }
                }
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Scoped to the overlay only — an implicit `.animation` on the whole view
                // caught the segmented-control pill mid-tap and animated it with the wrong curve.
                .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
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
            .alert("Delete Share Link?", isPresented: deleteConfirmationBinding) {
                Button("Delete", role: .destructive) { store.send(.deleteConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.deleteCancelled) }
            } message: {
                Text("The link stops working immediately. The file or folder itself isn't touched.")
            }
            .hapticFeedback(.warning, trigger: store.deleteConfirmationShare != nil)
            .dsToast($toastMessage)
            .task { store.send(.onAppear) }
            .onChange(of: store.externalRevision) { _, _ in store.send(.externalRevisionChanged) }
        }
        .tint(Color.accent)
    }

    private var emptyMessage: String {
        store.segment == .byMe
            ? "Share a file or folder to see its link here."
            : "Links other people share with you show up here."
    }

    private var shareList: some View {
        List {
            DSSegmentedControl(
                options: SharedFeature.Segment.allCases,
                selection: segment,
                label: { $0.title }
            )
            .padding(.top, Constants.segmentedControlTopPadding)
            .padding(.bottom, Constants.segmentedControlBottomPadding)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Constants.cardListInset, bottom: 0, trailing: Constants.cardListInset))

            section(for: store.activeShares, header: nil)
            if !store.expiredShares.isEmpty {
                section(for: store.expiredShares, header: "Expired")
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(Constants.cardListSpacing)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .refreshable {
            await store.send(.refreshRequested).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedShares
        )
    }

    @ViewBuilder
    private func section(for shares: IdentifiedArrayOf<Share>, header: String?) -> some View {
        Section {
            ForEach(shares) { share in
                SharedLinkCard(
                    share: share,
                    serverURL: store.serverURL,
                    isByMe: store.segment == .byMe,
                    isExpired: store.state.isExpired(share),
                    audience: store.state.audience(for: share),
                    sharedByText: store.state.sharedByLabel(for: share),
                    isDeleting: store.deletingIDs.contains(share.id),
                    onDelete: { store.send(.deleteTapped(share)) },
                    onCopied: { toastMessage = .success($0) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Constants.cardListSpacing / 2,
                    leading: Constants.cardListInset,
                    bottom: Constants.cardListSpacing / 2,
                    trailing: Constants.cardListInset
                ))
            }
        } header: {
            if let header {
                Text(header)
                    .type(.body3(.semibold), style: .secondary)
                    .textCase(.uppercase)
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
    let onCopied: (String) -> Void

    @State private var isExpanded: Bool
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
        self.onCopied = onCopied
        self._isExpanded = State(initialValue: startExpanded)
    }

    private enum Metrics {
        static let cornerRadius: CGFloat = .radiusMedium
        static let padding: CGFloat = .space16
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
                if isByMe { ownerBody } else { recipientBody }
            }
        }
        .background(RoundedRectangle(cornerRadius: Metrics.cornerRadius).fill(Color.backgroundSecondary))
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
            metaRow(accessIcon, "Access", share.accessMode.title)
            metaRow(IconKit.calendar, "Expiration", expiresText, isWarning: isExpired)
            linkModeRow

            HStack(spacing: Metrics.actionRowSpacing) {
                pillAction(IconKit.link, "Share link", tint: .accent, isEnabled: true) {
                    copy(shareLinkString, label: "Share link copied")
                }
                pillAction(
                    IconKit.copy,
                    share.isDirectory ? "Folder link" : "File link",
                    tint: .accent,
                    isEnabled: true
                ) {
                    copy(directLinkString, label: share.isDirectory ? "Folder ZIP link copied" : "Direct file link copied")
                }
            }

            pillAction(IconKit.delete, "Delete", tint: .negative, isEnabled: true, action: onDelete)
                .padding(.top, Metrics.actionRowSpacing)
        }
        .padding(Metrics.padding)
    }

    /// "With me": read-only — no link, no mode picker, no delete, matching the web
    /// `SharedWithMeView`. Just who shared it, the access level, and the expiry.
    private var recipientBody: some View {
        VStack(alignment: .leading, spacing: .space8) {
            metaRow(IconKit.person, "Shared by", sharedByText)
            metaRow(accessIcon, "Access", share.accessMode.title)
            metaRow(IconKit.calendar, "Expiration", expiresText, isWarning: isExpired)
        }
        .opacity(isExpired ? Metrics.expiredInfoOpacity : 1)
        .padding(Metrics.padding)
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
                Text("Shared with").type(.body2(.regular), style: .primary(for: .label))
                Spacer(minLength: .space8)
                if audienceIsAnyone {
                    Text("Anyone with link").type(.body2(.regular), style: .secondary)
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
        FlowLayout(horizontalSpacing: .space4, verticalSpacing: .space4) {
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
                Text("+\(unnamed)")
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

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: .space12) {
                (share.isDirectory ? IconKit.folderFill : IconKit.document)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)

                VStack(alignment: .leading, spacing: .space2) {
                    HStack(spacing: .space8) {
                        Text(share.displayName)
                            .type(.body2(.semibold), style: .primary(for: .label))
                            .lineLimit(1)
                        if isExpired {
                            Text("expired".uppercased())
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

                IconKit.chevronRight
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(Metrics.padding)
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
            Text("Link mode").type(.body2(.regular), style: .primary(for: .label))
            Spacer()
            Picker("Link mode", selection: $directLinkMode) {
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
        guard let expiresAt = share.expiresAt else { return "Never" }
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
