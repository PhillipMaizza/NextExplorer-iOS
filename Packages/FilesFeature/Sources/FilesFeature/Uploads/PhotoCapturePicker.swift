#if os(iOS)
    import SwiftUI
    import UIKit

    /// Camera capture pinned to stills, with the system crop step, handing back a `UIImage`.
    /// Separate from `CameraPicker` (which also does video and stages files for the upload flow)
    /// because the server-logo picker only wants a single square-ish photo in memory.
    struct PhotoCapturePicker: UIViewControllerRepresentable {
        let onCapture: (UIImage?) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let controller = UIImagePickerController()
            controller.sourceType = .camera
            controller.cameraCaptureMode = .photo
            controller.allowsEditing = true
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture)
        }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            private let onCapture: (UIImage?) -> Void

            init(onCapture: @escaping (UIImage?) -> Void) {
                self.onCapture = onCapture
            }

            func imagePickerController(
                _: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                onCapture(info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage)
            }

            func imagePickerControllerDidCancel(_: UIImagePickerController) {
                onCapture(nil)
            }
        }
    }
#endif
