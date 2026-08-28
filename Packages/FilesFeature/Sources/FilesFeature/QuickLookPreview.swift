import QuickLook
import SwiftUI

/// Thin `QLPreviewController` wrapper — the first UIKit-representable in this codebase.
/// Takes one or more local file URLs (see `FilesClient.previewFile`): `QLPreviewController`
/// reads each file's extension to pick the right renderer (image, PDF, text, office docs, ...),
/// which only works reliably against a local file, not a remote URL. With more than one URL
/// the built in controller lets the user swipe between them, starting at `initialIndex`, and
/// reports each page change back through `onIndexChange` so a caller's title can follow along.
struct QuickLookPreview: UIViewControllerRepresentable {
    let urls: [URL]
    let initialIndex: Int
    var onIndexChange: ((Int) -> Void)?

    init(urls: [URL], initialIndex: Int = 0, onIndexChange: ((Int) -> Void)? = nil) {
        self.urls = urls
        self.initialIndex = initialIndex
        self.onIndexChange = onIndexChange
    }

    init(url: URL) {
        self.init(urls: [url])
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        if urls.indices.contains(initialIndex) {
            controller.currentPreviewItemIndex = initialIndex
        }
        context.coordinator.startObserving(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.onIndexChange = onIndexChange
        // Guard against reloading on every SwiftUI re-render (an unrelated state change
        // elsewhere in the hosting view would otherwise reset QuickLook's scroll/zoom state).
        guard context.coordinator.urls != urls else { return }
        context.coordinator.urls = urls
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls, onIndexChange: onIndexChange)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var urls: [URL]
        var onIndexChange: ((Int) -> Void)?

        private static let indexKeyPath = "currentPreviewItemIndex"
        private weak var observed: QLPreviewController?

        init(urls: [URL], onIndexChange: ((Int) -> Void)?) {
            self.urls = urls
            self.onIndexChange = onIndexChange
        }

        /// KVO the built in controller's `currentPreviewItemIndex`: it bumps this as the user
        /// swipes across the batch, which is the only signal it gives that the page changed.
        func startObserving(_ controller: QLPreviewController) {
            observed = controller
            controller.addObserver(self, forKeyPath: Self.indexKeyPath, options: [.new], context: nil)
        }

        deinit {
            observed?.removeObserver(self, forKeyPath: Self.indexKeyPath)
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == Self.indexKeyPath, let index = change?[.newKey] as? Int else { return }
            let notify = onIndexChange
            DispatchQueue.main.async { notify?(index) }
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            urls[index] as NSURL
        }
    }
}
