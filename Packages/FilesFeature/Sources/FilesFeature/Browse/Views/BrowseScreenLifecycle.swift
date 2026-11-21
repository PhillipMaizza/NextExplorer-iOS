import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// What a Browse screen starts and stops as it comes and goes: its folder load, revealing a
/// search hit, the on device search and offline badges, and cancelling an open left mid way.
struct BrowseScreenLifecycle: ViewModifier {
    let store: StoreOf<BrowseFeature>
    let sourceVisibility: PreviewSourceVisibility
    @Binding var shareTarget: FileItem?
    @Binding var galleryCurrentItemID: String?

    func body(content: Content) -> some View {
        content
            // The share target is view local state; clear it whenever the preview closes so a
            // stale value can't reopen the share sheet over the next preview.
            .onChange(of: store.previewItem == nil) { _, previewClosed in
                if previewClosed {
                    shareTarget = nil
                    // Cleared after the dismiss morph has already captured the source id.
                    galleryCurrentItemID = nil
                }
            }
        #if os(iOS)
            .fileUndoRegistration(store.undoStack) { [store] in
                store.send(.undoTapped, animation: DSMotion.listDiff)
            }
        #endif
            .onAppear { sourceVisibility.isScreenVisible = true }
            .onDisappear {
                sourceVisibility.isScreenVisible = false
                // Leaving mid open (a tab switch or a push while a slow file still loads) cancels
                // it, like a second tap on the spinning row; the cover would otherwise appear over
                // another screen with nothing to zoom from. An open cover also takes this view off
                // screen, but by then its content is ready, so it is left alone.
                if store.previewItem != nil, !store.isPreviewContentReady {
                    // Next tick: a disappear driven by a reducer (a push) must not send reentrantly.
                    Task { @MainActor in store.send(.previewDismissed) }
                }
            }
            // Keyed on the folder: a jump to another folder at the same depth swaps this screen's store
            // under the same view, which must start loading it too.
            .task(id: store.directoryPath) {
                // Yield first so these sends land after whatever action presented this view has
                // finished reducing, never reentrantly during it (TCA forbids reentrant sends).
                await Task.yield()
                // Gone already (a jump replaced this screen): its element is no longer in the stack.
                guard !Task.isCancelled else { return }
                store.send(.onAppear)
                store.send(.computeOfflineAvailability)
            }
            // A search hit opened this folder: once its listing holds the file, select it.
            .task(id: RevealKey(
                id: store.revealItemID,
                isListed: store.revealItemID.map { store.items[id: $0] != nil }
            )) {
                guard let id = store.revealItemID, store.items[id: id] != nil else { return }
                store.send(.revealItemShown(id))
            }
            // New results, or a change in what this folder keeps offline: find the results on the device.
            .task(id: SearchOnDeviceKey(results: store.searchResults?.ids.elements, offline: store.offlineItemIDs)) {
                store.send(.computeSearchOnDevice)
            }
            // A finished offline download can change what's available here, so refresh the badges.
            // The completion mutates shared state, so this `onChange` fires mid reduce; hop to the next
            // tick so the send isn't reentrant.
            .onOfflinePhaseChange { phase in
                if phase == .completed {
                    Task { @MainActor in
                        store.send(.computeOfflineAvailability)
                        store.send(.computeSearchOnDevice)
                    }
                }
            }
    }
}

private struct RevealKey: Hashable {
    let id: String?
    let isListed: Bool?
}

#Preview {
    Text(verbatim: "")
        .modifier(BrowseScreenLifecycle(
            store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
            sourceVisibility: PreviewSourceVisibility(),
            shareTarget: .constant(nil),
            galleryCurrentItemID: .constant(nil)
        ))
}
