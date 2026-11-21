import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// The full screen preview a Browse screen opens, zooming from the tapped cell. It stays put
/// through downloads and renames, so their sheets and toasts are hosted over it too.
struct BrowsePreviewCover: View {
    let store: StoreOf<BrowseFeature>
    let item: FileItem
    let zoomContext: PreviewZoomContext
    @Binding var galleryCurrentItemID: String?
    @Binding var shareTarget: FileItem?
    @Binding var isDestinationPickerOnScreen: Bool
    @Binding var toastMessage: DSToastMessage?

    /// Lifts a toast clear of the `previewChrome` bottom action bar.
    private static let toolbarToastInset: CGFloat = .size56

    var body: some View {
        ZoomingPreview(
            sourceID: galleryCurrentItemID ?? item.id,
            context: zoomContext
        ) {
            BrowsePreviewRouter(
                store: store,
                item: item,
                onShareTarget: { shareTarget = $0 },
                onGalleryItemChange: { galleryCurrentItemID = $0.id }
            )
        }
        .modifier(BrowseActionSheets(
            store: store,
            inPreview: true,
            shareTarget: $shareTarget,
            isDestinationPickerOnScreen: $isDestinationPickerOnScreen
        ))
        // The preview stays put through downloads and renames: their result
        // toasts surface over the cover, and "Open" on a download routes back
        // through the reducer so the cover dismisses before the tab switches.
        .modifier(BrowseToasts(
            store: store,
            toastMessage: $toastMessage,
            inPreview: true,
            extraBottomInset: Self.toolbarToastInset
        ))
    }
}

#Preview {
    @Previewable @Namespace var namespace
    BrowsePreviewCover(
        store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
        item: browsePreviewItems[2],
        zoomContext: PreviewZoomContext(namespace: namespace, visibility: PreviewSourceVisibility()),
        galleryCurrentItemID: .constant(nil),
        shareTarget: .constant(nil),
        isDestinationPickerOnScreen: .constant(false),
        toastMessage: .constant(nil)
    )
}
