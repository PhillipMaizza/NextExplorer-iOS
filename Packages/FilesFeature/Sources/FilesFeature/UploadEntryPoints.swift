import AVFoundation
import DesignSystem
import Localization
import PhotosUI
import SwiftUI
import UIKit

private enum Constants {
    static let maxPhotoUploads = 20
}

/// Camera permission resolved *before* presenting `UIImagePickerController` — presenting it
/// first shows the system prompt mid transition and the camera stalls behind it. Returns
/// `true` when the picker may be shown, `false` when the caller should surface the denied
/// alert instead.
enum CameraAccess {
    @MainActor
    static func resolve() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

/// The three upload pickers (camera / Photos / Files) plus the camera denied alert, with no
/// UI of its own — the trigger (a toolbar `+`, an "Add more" row) lives at the call site and
/// flips these bindings. Shared by `UploadEntryPoints` and `UploadReviewView`.
struct UploadPickers: ViewModifier {
    @Binding var isFilesPickerPresented: Bool
    @Binding var isPhotosPickerPresented: Bool
    @Binding var isCameraPresented: Bool
    @Binding var isCameraDeniedAlertPresented: Bool
    @Binding var photosSelection: [PhotosPickerItem]
    let onDocumentsPicked: ([URL]) -> Void
    let onPhotosPicked: ([PhotosPickerItem]) -> Void
    let onPhotoCaptured: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .alert(L10n.Uploads.cameraDeniedTitle, isPresented: $isCameraDeniedAlertPresented) {
                Button(L10n.Common.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Uploads.cameraDeniedMessage)
            }
            .fileImporter(
                isPresented: $isFilesPickerPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result { onDocumentsPicked(urls) }
            }
            .photosPicker(
                isPresented: $isPhotosPickerPresented,
                selection: $photosSelection,
                maxSelectionCount: Constants.maxPhotoUploads,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: photosSelection) { _, items in
                guard !items.isEmpty else { return }
                onPhotosPicked(items)
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraPicker { url in
                    isCameraPresented = false
                    if let url { onPhotoCaptured(url) }
                }
                .ignoresSafeArea()
            }
    }
}

/// The `+` toolbar button and its picker menu (camera / Photos / Files). Extracted from
/// `BrowseContentView` so its `body` stays inside the type checker's budget. Each picker hands
/// back files the caller turns into `PickedFile`s; the destination is chosen afterwards.
struct UploadEntryPoints: ViewModifier {
    let isSelecting: Bool
    /// Gates the `+` on the folder's own `FileAccess.canUpload` — a read only folder never
    /// shows it, so a pick can't run headlong into a guaranteed 403.
    let canUpload: Bool
    @Binding var isFilesPickerPresented: Bool
    @Binding var isPhotosPickerPresented: Bool
    @Binding var isCameraPresented: Bool
    @Binding var photosSelection: [PhotosPickerItem]
    let onDocumentsPicked: ([URL]) -> Void
    let onPhotosPicked: ([PhotosPickerItem]) -> Void
    let onPhotoCaptured: (URL) -> Void

    @State private var isCameraDeniedAlertPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !isSelecting && canUpload {
                    ToolbarItem(placement: .topBarTrailing) {
                        UploadSourceMenu(
                            label: { IconKit.plus.foregroundStyle(Color.primaryDS) },
                            isFilesPickerPresented: $isFilesPickerPresented,
                            isPhotosPickerPresented: $isPhotosPickerPresented,
                            isCameraPresented: $isCameraPresented,
                            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
                        )
                        .accessibilityLabel(L10n.Uploads.menuTitle)
                    }
                }
            }
            .modifier(UploadPickers(
                isFilesPickerPresented: $isFilesPickerPresented,
                isPhotosPickerPresented: $isPhotosPickerPresented,
                isCameraPresented: $isCameraPresented,
                isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented,
                photosSelection: $photosSelection,
                onDocumentsPicked: onDocumentsPicked,
                onPhotosPicked: onPhotosPicked,
                onPhotoCaptured: onPhotoCaptured
            ))
    }
}

/// Take Photo / Upload from Photos / Upload from Files — the shared menu behind both the
/// browse `+` and the review sheet's "Add more files" row.
struct UploadSourceMenu<MenuLabel: View>: View {
    @ViewBuilder let label: () -> MenuLabel
    @Binding var isFilesPickerPresented: Bool
    @Binding var isPhotosPickerPresented: Bool
    @Binding var isCameraPresented: Bool
    @Binding var isCameraDeniedAlertPresented: Bool

    var body: some View {
        // `.menuOrder(.fixed)`: keep Take Photo first even from the review sheet's "Add more"
        // button, where the menu opens upward and the default order would flip.
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    Task {
                        if await CameraAccess.resolve() {
                            isCameraPresented = true
                        } else {
                            isCameraDeniedAlertPresented = true
                        }
                    }
                } label: {
                    Label { Text(L10n.Uploads.actionTakePhoto) } icon: { IconKit.camera }
                }
            }
            Button {
                isPhotosPickerPresented = true
            } label: {
                Label { Text(L10n.Uploads.actionUploadFromPhotos) } icon: { IconKit.photo }
            }
            Button {
                isFilesPickerPresented = true
            } label: {
                Label { Text(L10n.Uploads.actionUploadFromFiles) } icon: { IconKit.folder }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
    }
}
