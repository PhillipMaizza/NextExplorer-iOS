import DesignSystem
import SwiftUI

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
