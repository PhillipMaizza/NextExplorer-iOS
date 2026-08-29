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
    var onIndexChange: (@MainActor (Int) -> Void)?

    init(urls: [URL], initialIndex: Int = 0, onIndexChange: (@MainActor (Int) -> Void)? = nil) {
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
        if let onIndexChange {
            context.coordinator.indexObserver = QLIndexObserver(observing: controller, onChange: onIndexChange)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Guard against reloading on every SwiftUI re-render (an unrelated state change
        // elsewhere in the hosting view would otherwise reset QuickLook's scroll/zoom state).
        guard context.coordinator.urls != urls else { return }
        context.coordinator.urls = urls
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var urls: [URL]
        var indexObserver: QLIndexObserver?

        init(urls: [URL]) {
            self.urls = urls
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            urls[index] as NSURL
        }
    }
}

/// KVO on `QLPreviewController.currentPreviewItemIndex` — the only signal the built in
/// controller gives that the user swiped to another page. Kept as its own plain `NSObject`,
/// deliberately not the `@MainActor` `QLPreviewControllerDataSource` coordinator, so the
/// nonisolated `observeValue` override can touch this object's own state without an unchecked
/// escape. The callback is hopped onto the main actor before it runs, whatever thread KVO
/// delivered the change on.
final class QLIndexObserver: NSObject {
    private static let keyPath = "currentPreviewItemIndex"
    private weak var controller: QLPreviewController?
    private let onChange: @MainActor (Int) -> Void

    init(observing controller: QLPreviewController, onChange: @escaping @MainActor (Int) -> Void) {
        self.controller = controller
        self.onChange = onChange
        super.init()
        controller.addObserver(self, forKeyPath: Self.keyPath, options: [.new], context: nil)
    }

    deinit {
        controller?.removeObserver(self, forKeyPath: Self.keyPath)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.keyPath, let index = change?[.newKey] as? Int else { return }
        let onChange = self.onChange
        Task { @MainActor in onChange(index) }
    }
}
