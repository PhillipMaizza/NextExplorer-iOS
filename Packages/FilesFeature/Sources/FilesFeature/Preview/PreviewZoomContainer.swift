import DesignSystem
import SwiftUI

/// Identifies the exact source view a full-screen preview's `.zoom` transition should grow
/// from — the file's thumbnail/icon inside its row or grid cell, not the whole-width row.
/// Threaded from `BrowseContentView` / `DownloadsView` into `FileRowView` / `GridCellView`.
struct PreviewMatchedSource {
    let id: AnyHashable
    let namespace: Namespace.ID
}

extension View {
    /// Marks this view as the `.zoom` transition source for `source`, or leaves it untouched
    /// when there is none (a folder row, a screen with no preview cover).
    @ViewBuilder
    func previewMatchedSource(_ source: PreviewMatchedSource?) -> some View {
        if let source {
            matchedTransitionSource(id: source.id, in: source.namespace)
        } else {
            self
        }
    }
}

extension View {
    /// Scrolls the file whose id matches the open gallery's current page to center, so the
    /// cover's `.zoom` dismiss morphs back to an on-screen cell after the user swipes between
    /// images. Runs while the full-screen cover covers the list, so the reposition is unseen.
    func scrollGalleryPageIntoView(_ proxy: ScrollViewProxy, id: String?) -> some View {
        onChange(of: id) { _, newID in
            guard let newID else { return }
            proxy.scrollTo(newID, anchor: .center)
        }
    }
}

/// Wraps a full-screen file preview presented in a `.fullScreenCover` so its native `.zoom`
/// open/dismiss morph (see `BrowseContentView` / `DownloadsView`) reads against the app
/// background gradient rather than the cover's default black: the content is pinned full
/// bleed over `backgroundGradient()`, and the whole stack — gradient included — is the
/// transition subject, so the gradient fills every gap the morphing card leaves.
struct PreviewZoomContainer<ID: Hashable, Content: View>: View {
    let sourceID: ID
    let namespace: Namespace.ID
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
            .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    }
}
