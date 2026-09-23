import DesignSystem
import SwiftUI

/// Identifies the exact source view a full-screen preview's `.zoom` transition should grow
/// from — the file's thumbnail/icon inside its row or grid cell, not the whole-width row.
/// Threaded from `BrowseContentView` / `DownloadsView` into `FileRowView` / `GridCellView`.
struct PreviewMatchedSource {
    let id: AnyHashable
    let namespace: Namespace.ID
    /// When set, the source reports whether it is currently in the view hierarchy, so a cover
    /// that opens late (a slow load) can skip the zoom instead of morphing from a missing view.
    var visibility: PreviewSourceVisibility?
}

/// Which zoom sources are on screen right now. A plain reference, not observed, so rows
/// appearing and disappearing while scrolling never re-render the screen that owns it.
final class PreviewSourceVisibility {
    private var visibleIDs = Set<AnyHashable>()
    var isScreenVisible = false

    func setVisible(_ visible: Bool, id: AnyHashable) {
        if visible {
            visibleIDs.insert(id)
        } else {
            visibleIDs.remove(id)
        }
    }

    /// UIKit crashes ("Cannot morph from a view that is not in the hierarchy") when a zoom
    /// starts from a source that left the screen, e.g. after a tab switch or a scroll during a
    /// slow open.
    func canZoom(from id: AnyHashable) -> Bool {
        isScreenVisible && visibleIDs.contains(id)
    }
}

extension View {
    /// Marks this view as the `.zoom` transition source for `source`, or leaves it untouched
    /// when there is none (a folder row, a screen with no preview cover).
    @ViewBuilder
    func previewMatchedSource(_ source: PreviewMatchedSource?) -> some View {
        if let source {
            matchedTransitionSource(id: source.id, in: source.namespace)
                .onAppear { source.visibility?.setVisible(true, id: source.id) }
                .onDisappear { source.visibility?.setVisible(false, id: source.id) }
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
///
/// `zooms` false falls back to the standard cover transition, for when the source is gone.
struct PreviewZoomContainer<ID: Hashable, Content: View>: View {
    let sourceID: ID
    let namespace: Namespace.ID
    var zooms = true
    @ViewBuilder let content: Content

    var body: some View {
        if zooms {
            framedContent
                .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            framedContent
        }
    }

    private var framedContent: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
    }
}
