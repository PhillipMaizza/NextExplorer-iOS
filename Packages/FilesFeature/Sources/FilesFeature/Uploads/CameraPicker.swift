import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Thin `UIImagePickerController` wrapper pinned to the camera — SwiftUI has no native camera
/// capture. Offers both capture modes so the system camera shows its Photo/Video switch;
/// `allowsEditing` gives the built in trim/crop step after the shot. Hands back a file written
/// into `UploadStagingLocation` (a JPEG for a photo, the recorded movie for a video), or nil
/// if the user cancels.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        controller.videoQuality = .typeHigh
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (URL?) -> Void

        init(onCapture: @escaping (URL?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let movieURL = info[.mediaURL] as? URL {
                onCapture(stagedCopy(of: movieURL))
                return
            }
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
                onCapture(nil)
                return
            }
            let url = UploadStagingLocation.directory
                .appendingPathComponent("Photo_\(Int(Date().timeIntervalSince1970)).jpg")
            onCapture((try? data.write(to: url)) != nil ? url : nil)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onCapture(nil)
        }

        /// The recorded movie lands in a system temp path that doesn't outlive this callback,
        /// so it's moved into the staging folder the rest of the upload flow reads from.
        private func stagedCopy(of movieURL: URL) -> URL? {
            let ext = movieURL.pathExtension.isEmpty ? "mov" : movieURL.pathExtension
            let destination = UploadStagingLocation.directory
                .appendingPathComponent("Video_\(Int(Date().timeIntervalSince1970)).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.moveItem(at: movieURL, to: destination)) != nil else { return nil }
            return destination
        }
    }
}
