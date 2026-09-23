import AVFoundation
import DesignSystem
import Localization
import PhotosUI
import SwiftUI
#if os(iOS)
    import UIKit
#endif

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
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
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
            .sheet(isPresented: $isCameraDeniedAlertPresented) {
                DSAlertSheet(
                    icon: IconKit.camera,
                    title: L10n.Uploads.cameraDeniedTitle,
                    message: L10n.Uploads.cameraDeniedMessage,
                    confirmTitle: L10n.Common.openSettings,
                    dismissTitle: L10n.Common.cancel,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: {
                        isCameraDeniedAlertPresented = false
                        #if os(iOS)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        #endif
                    },
                    onDismiss: { isCameraDeniedAlertPresented = false }
                )
            }
            .fileImporter(
                isPresented: $isFilesPickerPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    onDocumentsPicked(urls)
                }
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
        #if os(iOS)
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraPicker { url in
                    isCameraPresented = false
                    if let url {
                        onCameraCaptured(url)
                    }
                }
                .ignoresSafeArea()
            }
        #endif
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
        _isFilesPickerPresented = isFilesPickerPresented
        _isPhotosPickerPresented = isPhotosPickerPresented
        _isCameraPresented = isCameraPresented
        _isCameraDeniedAlertPresented = isCameraDeniedAlertPresented
    }

    var body: some View {
        // `.menuOrder(.fixed)`: keep Take Photo first even from the review sheet's "Add more"
        // button, where the menu opens upward and the default order would flip.
        Menu {
            leadingActions()
            #if os(iOS)
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
            #endif
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

private enum DashedLabelConstants {
    static let dash: CGFloat = 4
    static let borderWidth: CGFloat = 1
    static let iconTextSpacing: CGFloat = .space4
    static let verticalPadding: CGFloat = .space12
}

/// Dashed outline "add / upload" label: a leading `+`, secondary text, a dashed
/// `.radiusControl` border. Shared by the review sheet's "Add more files" row and the empty
/// folder's upload call to action so the two read as the same control.
struct UploadDashedLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: DashedLabelConstants.iconTextSpacing) {
            IconKit.plus
                .resizable().scaledToFit()
                .frame(width: .iconSmall, height: .iconSmall)
            Text(title).type(.body2(.regular), style: .secondary)
        }
        .foregroundStyle(Color.secondaryDS)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashedLabelConstants.verticalPadding)
        .overlay(
            RoundedRectangle(cornerRadius: .radiusControl)
                .stroke(
                    Color.secondaryDS,
                    style: StrokeStyle(lineWidth: DashedLabelConstants.borderWidth, dash: [DashedLabelConstants.dash])
                )
        )
        .contentShape(Rectangle())
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
