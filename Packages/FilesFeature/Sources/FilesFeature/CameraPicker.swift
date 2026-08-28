import SwiftUI
import UIKit

/// Thin `UIImagePickerController` wrapper pinned to the camera — SwiftUI has no native camera
/// capture. `allowsEditing` gives the built in crop/scale step after the shot. Hands back a
/// JPEG written to a temp file (nil if the user cancels).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (URL?) -> Void

        init(onCapture: @escaping (URL?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
                onCapture(nil)
                return
            }
            let url = UploadStagingLocation.directory
                .appendingPathComponent("Photo_\(Int(Date().timeIntervalSince1970)).jpg")
            onCapture((try? data.write(to: url)) != nil ? url : nil)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
