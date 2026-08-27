import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import UIKit

private enum Constants {
    static let segmentedControlHorizontalPadding: CGFloat = .space16
    static let segmentedControlTopPadding: CGFloat = .space8
    static let segmentedControlBottomPadding: CGFloat = .space12
    static let cardListInset: CGFloat = .space8
    static let overlayCrossfadeDuration: Double = 0.2
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
}

struct SharedView: View {
    @Bindable var store: StoreOf<SharedFeature>
    @State private var toastMessage: DSToastMessage?
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
        case none, loading, error, empty
    }

    private var overlayState: OverlayState {
        if store.isLoading && store.isCurrentSegmentEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if store.isCurrentSegmentEmpty {
            .empty
        } else {
            .none
        }
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

                shareList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundPrimary)
            .navigationTitle("Shared")
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
                    case .none:
                        EmptyView()
                    }
                }
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
            .alert("Delete Share Link?", isPresented: deleteConfirmationBinding) {
                Button("Delete", role: .destructive) { store.send(.deleteConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.deleteCancelled) }
            } message: {
                Text("The link stops working immediately. The file or folder itself isn't touched.")
            }
            .hapticFeedback(.warning, trigger: store.deleteConfirmationShare != nil)
            .dsToast($toastMessage)
            .task { store.send(.onAppear) }
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
            ForEach(store.displayedShares) { share in
                SharedLinkCard(
                    share: share,
                    serverURL: store.serverURL,
                    isByMe: store.segment == .byMe,
                    isDeleting: store.deletingIDs.contains(share.id),
                    onDelete: { store.send(.deleteTapped(share)) },
                    onCopied: { toastMessage = .success($0) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Constants.cardListInset, leading: Constants.cardListInset, bottom: Constants.cardListInset, trailing: Constants.cardListInset))
            }
        }
        .listStyle(.plain)
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
}

/// One share on the Shared tab: a collapsed header (name + path) that expands to its
/// metadata and per-link actions (copy file link / copy share link / change direct-link
/// mode / delete). "With me" shares hide the path and the delete action.
private struct SharedLinkCard: View {
    let share: Share
    let serverURL: URL
    let isByMe: Bool
    let isDeleting: Bool
    let onDelete: () -> Void
    let onCopied: (String) -> Void

    @State private var isExpanded = false
    @State private var directLinkMode: DirectLinkMode = .auto

    private enum Metrics {
        static let cornerRadius: CGFloat = .radiusMedium
        static let padding: CGFloat = .space12
        static let sectionSpacing: CGFloat = .space12
        static let iconSize: CGFloat = .iconMedium
        static let metaIconSize: CGFloat = .iconXSmall
        static let chevronSize: CGFloat = .iconXSmall
        static let actionIconSize: CGFloat = .iconSmall
        static let expandAnimationDuration: Double = 0.2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    metaRow(IconKit.people, "Shared with", share.sharingType.title)
                    metaRow(IconKit.lock, "Access", share.accessMode.title)
                    metaRow(IconKit.calendar, "Expiration", expiresText, isWarning: share.isExpired)

                    Divider()

                    actionRow(IconKit.link, "Copy file link") { copy(directLinkString, label: "File link copied") }
                    actionRow(IconKit.copy, "Copy share link") { copy(shareLinkString, label: "Share link copied") }

                    HStack {
                        IconKit.shareLink
                            .resizable().scaledToFit()
                            .foregroundStyle(Color.secondaryDS)
                            .frame(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
                        Text("Link mode").type(.body2(.regular), style: .primary(for: .label))
                        Spacer()
                        Picker("Link mode", selection: $directLinkMode) {
                            ForEach(DirectLinkMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.secondaryDS)
                    }

                    if isByMe {
                        actionRow(IconKit.delete, "Delete", isDestructive: true, action: onDelete)
                    }
                }
                .padding(Metrics.padding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: Metrics.cornerRadius).fill(Color.backgroundSecondary))
        .opacity(isDeleting ? 0.4 : 1)
        .disabled(isDeleting)
        .animation(.easeInOut(duration: Metrics.expandAnimationDuration), value: isExpanded)
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
                    Text(share.displayName)
                        .type(.body2(.semibold), style: .primary(for: .label))
                        .lineLimit(1)
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

    private func metaRow(_ icon: Image, _ label: String, _ value: String, isWarning: Bool = false) -> some View {
        HStack(spacing: .space8) {
            icon
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(label).type(.body3(.regular), style: .secondary)
            Spacer()
            Text(value).type(.body3(.semibold), style: isWarning ? .error : .primary(for: .label))
        }
    }

    private func actionRow(_ icon: Image, _ title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: .space8) {
                icon
                    .resizable().scaledToFit()
                    .frame(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
                Text(title).type(.body2(.regular))
                Spacer()
            }
            .foregroundStyle(isDestructive ? Color.negative : Color.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
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
        formatter.timeStyle = .none
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
