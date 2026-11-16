import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Toasts split by surface: while a preview cover is up, its toasts render over the cover,
/// otherwise over the list. One `toastMessage` and `fileActionProgressMessage` still drive
/// both: only the visible one is bound.
struct BrowseToasts: ViewModifier {
    let store: StoreOf<BrowseFeature>
    @Binding var toastMessage: DSToastMessage?
    let inPreview: Bool
    let extraBottomInset: CGFloat

    private var isFrontmost: Bool {
        (store.previewItem != nil) == inPreview
    }

    func body(content: Content) -> some View {
        content
            .dsToast(messageBinding, extraBottomInset: extraBottomInset)
            .dsToast(progressBinding, extraBottomInset: extraBottomInset)
    }

    private var messageBinding: Binding<DSToastMessage?> {
        Binding(get: { isFrontmost ? toastMessage : nil }, set: { toastMessage = $0 })
    }

    /// Read only from the store's perspective: `fileActionProgressMessage` clears itself once
    /// the extract or compress effect resolves, so there is nothing for the view to write back:
    /// the toast has no auto dismiss timer to fire early either (`DSToastMessage.progress`
    /// sets `isPersistent`), so the setter is genuinely never called in practice.
    private var progressBinding: Binding<DSToastMessage?> {
        Binding(
            get: { isFrontmost ? store.fileActionProgressMessage.map(DSToastMessage.progress) : nil },
            set: { _ in }
        )
    }
}

/// Turns the reducer's result and error messages into toasts.
struct BrowseToastEvents: ViewModifier {
    let store: StoreOf<BrowseFeature>
    @Binding var toastMessage: DSToastMessage?

    func body(content: Content) -> some View {
        content
            // `fileActionErrorMessage` (rename/delete/extract/compress failures) was set on
            // `State` but never actually read by any view: silently swallowed. Mirrored into
            // the same toast the unsupported-file-type warning uses.
            .onChange(of: store.fileActionErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue)
            }
            .onChange(of: store.downloadSuccessMessage) { _, newValue in
                guard let newValue else { return }
                let inPreview = store.previewItem != nil
                toastMessage = .success(newValue, actionTitle: L10n.Browse.open) {
                    // From a preview, close the cover first, then switch tabs after a settle.
                    store.send(inPreview ? .openDownloadsFromPreview : .delegate(.openDownloadsTapped))
                }
            }
            .onChange(of: store.transferSuccessMessage) { _, newValue in
                guard let newValue else { return }
                // The toast offers the undo itself: a phone has no ⌘Z at hand, and on the Mac a
                // drag leaves focus where ⌘Z may not reach the file table.
                if !store.undoStack.isEmpty {
                    toastMessage = .success(newValue, actionTitle: L10n.Menu.undo) {
                        store.send(.undoTapped, animation: DSMotion.listDiff)
                    }
                    return
                }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.trashNotice) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(L10n.Trash.movedToTrash(newValue.count), actionTitle: L10n.Trash.openTrash) {
                    store.send(.delegate(.openTrashTapped))
                }
            }
            .onChange(of: store.clipboardStagedMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.transferErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .failure(newValue, actionTitle: L10n.Common.retry) {
                    store.send(.retryTransferTapped, animation: DSMotion.listDiff)
                }
            }
    }
}
