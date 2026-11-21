import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The toolbar's `+` menu: a new folder or file here, then the camera, Photos and Files uploads.
struct BrowseUploadMenu: View {
    let store: StoreOf<BrowseFeature>
    @Binding var isFilesPickerPresented: Bool
    @Binding var isPhotosPickerPresented: Bool
    @Binding var isCameraPresented: Bool
    @Binding var isCameraDeniedAlertPresented: Bool

    var body: some View {
        UploadSourceMenu(
            label: { IconKit.plus.foregroundStyle(Color.primaryDS) },
            leadingActions: {
                if !store.directoryPath.isEmpty {
                    if store.canCreateFolderHere {
                        Button { store.send(.newFolderTapped) } label: {
                            Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                        }
                    }
                    if store.canCreateFileHere {
                        Button { store.send(.newFileTapped) } label: {
                            Label { Text(L10n.Browse.actionNewFile) } icon: { IconKit.newFile }
                        }
                    }
                }
            },
            shouldIncludeUploadSources: store.canUploadHere,
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .accessibilityLabelWithTooltip(L10n.Uploads.menuTitle)
        .accessibilityIdentifier(AccessibilityIdentifiers.Browse.uploadMenu)
    }
}

#Preview {
    BrowseUploadMenu(
        store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
        isFilesPickerPresented: .constant(false),
        isPhotosPickerPresented: .constant(false),
        isCameraPresented: .constant(false),
        isCameraDeniedAlertPresented: .constant(false)
    )
}
