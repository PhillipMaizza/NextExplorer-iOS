import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The sheet a Shared row opens, one per item. It holds its own navigation: an item with one
/// share opens straight on that share's page, several open on a list that pushes each page, and a
/// page pushes Edit. Delete and the toasts present from here so they stack on top of the sheet.
struct SharedDetailSheet: View {
    @Bindable var store: StoreOf<SharedFeature>
    /// The detail as presented, kept for the slide out after the store has cleared it.
    let presented: SharedFeature.Detail

    @State private var toast: DSToastMessage?
    /// The last item shown, so the sheet keeps its content while it slides away after the item
    /// itself is gone (its last share deleted).
    @State private var lastItem: SharedFeature.Item?

    private var detail: SharedFeature.Detail {
        store.detail ?? presented
    }

    private var path: Binding<[Share.ID]> {
        Binding(
            get: { detail.pushedShareID.map { [$0] } ?? [] },
            set: { store.send(.detailShareSelected($0.last)) }
        )
    }

    var body: some View {
        let item = store.state.item(for: detail) ?? lastItem
        NavigationStack(path: path) {
            Group {
                if let item {
                    if item.shares.count > 1 {
                        SharedShareList(store: store, item: item, onCopied: showCopied)
                    } else {
                        page(item: item, share: item.shares[0])
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { store.send(.detailDismissed) } label: {
                        IconKit.close.foregroundStyle(Color.primaryDS)
                    }
                    .accessibilityLabel(L10n.Common.close)
                }
            }
            .navigationDestination(for: Share.ID.self) { id in
                SharedPushedPage(
                    store: store,
                    presented: presented,
                    shareID: id,
                    fallback: item,
                    onCopied: showCopied
                )
            }
        }
        .tint(Color.accent)
        .interactiveDismissDisabled(store.editSheet?.isLeavingGuarded == true)
        .modifier(SharedActionPresentations(store: store, toast: $toast))
        .dsToast($toast)
        .onChange(of: item, initial: true) { _, newItem in
            if let newItem {
                lastItem = newItem
            }
        }
    }

    private func page(item: SharedFeature.Item, share: Share) -> some View {
        SharedSharePage(
            store: store,
            segment: detail.segment,
            item: item,
            share: share,
            isPushed: false,
            onCopied: showCopied
        )
    }

    private func showCopied(_ text: String) {
        toast = .success(text)
    }
}

/// A pushed share page that reads its share from the store itself. SwiftUI keeps a pushed
/// destination as it was built, so a share handed in from the sheet's body would go stale and
/// miss a saved edit.
private struct SharedPushedPage: View {
    let store: StoreOf<SharedFeature>
    let presented: SharedFeature.Detail
    let shareID: Share.ID
    let fallback: SharedFeature.Item?
    let onCopied: (String) -> Void

    var body: some View {
        let detail = store.detail ?? presented
        if let item = store.state.item(for: detail) ?? fallback,
           let share = item.shares.first(where: { $0.id == shareID })
        {
            SharedSharePage(
                store: store,
                segment: detail.segment,
                item: item,
                share: share,
                isPushed: true,
                onCopied: onCopied
            )
        }
    }
}

/// A single mock share, for previews outside the Shared tab.
extension Share {
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

/// The server every Shared preview pretends to talk to.
let sharedPreviewServerURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

/// Shared state over the mock lists, loaded, with names resolved, for previews.
@MainActor
func sharedPreviewState(mutate: (inout SharedFeature.State) -> Void = { _ in }) -> SharedFeature.State {
    var state = SharedFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"))
    state.now = Date()
    state.userNames = Dictionary(uniqueKeysWithValues: Share.previewShareableUsers.map { (
        $0.id,
        $0.displayName ?? $0.username
    ) })
    state.byMe = IdentifiedArray(uniqueElements: Share.previewSharedByMe)
    state.withMe = IdentifiedArray(uniqueElements: Share.previewSharedWithMe)
    state.phases = [.byMe: .loaded, .withMe: .loaded]
    mutate(&state)
    return state
}

@MainActor
func sharedPreviewStore(mutate: (inout SharedFeature.State) -> Void = { _ in }) -> StoreOf<SharedFeature> {
    Store(initialState: sharedPreviewState(mutate: mutate)) { SharedFeature() } withDependencies: {
        $0.filesClient = .previewValue
    }
}

/// A Shared store over the mock lists, opened on one item's sheet, for the sheet's previews.
@MainActor
func sharedDetailPreview(
    _ segment: SharedFeature.Segment,
    _ itemID: SharedFeature.Item.ID,
    pushed: Share.ID? = nil,
    mutate: (inout SharedFeature.State) -> Void = { _ in }
) -> some View {
    let detail = SharedFeature.Detail(segment: segment, id: itemID, pushedShareID: pushed)
    let store = sharedPreviewStore { state in
        state.detail = detail
        mutate(&state)
    }
    return SharedDetailSheet(store: store, presented: detail)
}

#Preview("Sheet: one share") {
    sharedDetailPreview(.byMe, "personal:Documents/Bills/Electricity")
}

#Preview("Sheet: several shares") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap")
}

#Preview("Sheet: pushed share, dark") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap", pushed: "s6")
        .preferredColorScheme(.dark)
}

#Preview("Sheet: with me") {
    sharedDetailPreview(.withMe, "s3")
}
