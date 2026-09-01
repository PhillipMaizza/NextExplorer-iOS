import DesignSystem
import SwiftUI

/// Full screen preview for a staged file, opened from its row thumbnail. Goes through
/// `QuickLook`, which swipes across the whole batch starting on the tapped file. Wrapped in a
/// `NavigationStack` so `previewChrome` can hang a close button off it — `QLPreviewController`
/// only draws its own Done bar when UIKit presents it directly, not through a representable.
struct PickedFilePreview: View {
    let urls: [URL]
    let names: [String]
    let initialIndex: Int
    let onClose: () -> Void

    @State private var currentIndex: Int

    init(urls: [URL], names: [String], initialIndex: Int, onClose: @escaping () -> Void) {
        self.urls = urls
        self.names = names
        self.initialIndex = initialIndex
        self.onClose = onClose
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var title: String? {
        names.indices.contains(currentIndex) ? names[currentIndex] : nil
    }

    var body: some View {
        NavigationStack {
            QuickLookPreview(urls: urls, initialIndex: initialIndex) { currentIndex = $0 }
                .ignoresSafeArea()
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .previewChrome(title: title, onClose: onClose)
        }
    }
}
