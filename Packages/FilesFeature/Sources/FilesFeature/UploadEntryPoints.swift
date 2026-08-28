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
    let onCameraCaptured: (URL) -> Void

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
                    if let url { onCameraCaptured(url) }
                }
                .ignoresSafeArea()
            }
    }
}

/// Take Photo or Video / Upload from Gallery / Upload from Files — the shared menu behind both
/// the browse `+` and the review sheet's "Add more files" row.
struct UploadSourceMenu<MenuLabel: View, LeadingActions: View>: View {
    private let label: () -> MenuLabel
    /// Extra items above the upload sources — the browse `+` slots "Create Folder" here; the
    /// review sheet's "Add more" leaves it empty.
    private let leadingActions: () -> LeadingActions
    @Binding private var isFilesPickerPresented: Bool
    @Binding private var isPhotosPickerPresented: Bool
    @Binding private var isCameraPresented: Bool
    @Binding private var isCameraDeniedAlertPresented: Bool

    init(
        @ViewBuilder label: @escaping () -> MenuLabel,
        @ViewBuilder leadingActions: @escaping () -> LeadingActions,
        isFilesPickerPresented: Binding<Bool>,
        isPhotosPickerPresented: Binding<Bool>,
        isCameraPresented: Binding<Bool>,
        isCameraDeniedAlertPresented: Binding<Bool>
    ) {
        self.label = label
        self.leadingActions = leadingActions
        self._isFilesPickerPresented = isFilesPickerPresented
        self._isPhotosPickerPresented = isPhotosPickerPresented
        self._isCameraPresented = isCameraPresented
        self._isCameraDeniedAlertPresented = isCameraDeniedAlertPresented
    }

    var body: some View {
        // `.menuOrder(.fixed)`: keep Take Photo first even from the review sheet's "Add more"
        // button, where the menu opens upward and the default order would flip.
        Menu {
            leadingActions()
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

extension UploadSourceMenu where LeadingActions == EmptyView {
    init(
        @ViewBuilder label: @escaping () -> MenuLabel,
        isFilesPickerPresented: Binding<Bool>,
        isPhotosPickerPresented: Binding<Bool>,
        isCameraPresented: Binding<Bool>,
        isCameraDeniedAlertPresented: Binding<Bool>
    ) {
        self.init(
            label: label,
            leadingActions: { EmptyView() },
            isFilesPickerPresented: isFilesPickerPresented,
            isPhotosPickerPresented: isPhotosPickerPresented,
            isCameraPresented: isCameraPresented,
            isCameraDeniedAlertPresented: isCameraDeniedAlertPresented
        )
    }
}
