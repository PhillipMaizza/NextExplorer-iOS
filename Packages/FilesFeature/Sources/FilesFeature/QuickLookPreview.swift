import QuickLook
import SwiftUI

/// Thin `QLPreviewController` wrapper — the first UIKit-representable in this codebase.
/// Takes a single local file URL (see `FilesClient.previewFile`): `QLPreviewController`
/// reads the file's extension to pick the right renderer (image, PDF, text, office docs, ...),
/// which only works reliably against a local file, not a remote URL.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Guard against reloading on every SwiftUI re-render (an unrelated state change
        // elsewhere in the hosting view would otherwise reset QuickLook's scroll/zoom state).
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
