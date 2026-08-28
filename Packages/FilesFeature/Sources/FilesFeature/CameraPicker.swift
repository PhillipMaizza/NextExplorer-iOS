import SwiftUI
import UIKit

/// Thin `UIImagePickerController` wrapper pinned to the camera — SwiftUI has no native camera
/// capture. Hands back a JPEG written to a temp file (nil if the user cancels).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
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
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCapture(nil)
                return
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PendingUploads", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Photo_\(Int(Date().timeIntervalSince1970)).jpg")
            onCapture((try? data.write(to: url)) != nil ? url : nil)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
