import AVFoundation
import DesignSystem
import Localization
import PhotosUI
import SwiftUI
import UIKit

private enum Constants {
    static let maxPhotoUploads = 20
}

/// The `+` toolbar button and its three pickers (camera / Photos / Files). Extracted from
/// `BrowseContentView` so its `body` stays inside the type-checker's budget. Each picker hands
/// back files the caller turns into `PickedFile`s; the destination is chosen afterwards.
struct UploadEntryPoints: ViewModifier {
    let isSelecting: Bool
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
                if !isSelecting {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
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

    private var menu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    Task { await presentCamera() }
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
            IconKit.plus.foregroundStyle(Color.primaryDS)
        }
        .accessibilityLabel(L10n.Uploads.menuTitle)
    }

    /// Resolve camera permission *before* presenting `UIImagePickerController` — presenting it
    /// first shows the system prompt mid-transition and the camera stalls behind it.
    @MainActor
    private func presentCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                isCameraPresented = true
            }
        default:
            isCameraDeniedAlertPresented = true
        }
    }
}
