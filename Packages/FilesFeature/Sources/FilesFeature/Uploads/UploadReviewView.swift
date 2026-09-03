import ComposableArchitecture
import CoreModels
import DesignSystem
import Foundation
import Localization
import PhotosUI
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let sectionRowSpacing: CGFloat = .space16
    static let cellVerticalPadding: CGFloat = .space16
    static let cellHorizontalPadding: CGFloat = .space16
    static let rowSpacing: CGFloat = .space12
    static let rowTextSpacing: CGFloat = .space2
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let enabledOpacity: Double = 1
    static let disabledOpacity: Double = 0.35
    /// The sheet fits its content but never exceeds this fraction of the screen — past that
    /// the file list scrolls and `.large` is a drag away.
    static let maxHeightFraction: CGFloat = 0.9
}

/// The review sheet: what's about to upload, where to, how big, and the Upload button.
struct UploadReviewView: View {
    @Bindable var store: StoreOf<UploadReviewFeature>

    @State private var isFilesPickerPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isCameraDeniedAlertPresented = false
    @State private var photosSelection: [PhotosPickerItem] = []
    @State private var previewSelection: PreviewSelection?

    /// The staged file whose full screen QuickLook preview is open; `id` is the row's
    /// `PickedFile.ID` so the preview can open on it and still swipe across the whole list.
    private struct PreviewSelection: Identifiable, Equatable {
        let id: PickedFile.ID
    }

    private func rowIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.secondaryDS)
            .frame(width: .iconSmall, height: .iconSmall)
    }

    /// "Add more files" — opens the same camera / Photos / Files menu the browse `+` uses,
    /// streaming the new pick into this same sheet. A clear, dashed outline button that sits
    /// in the bottom bar above Upload (not a list cell, which would clip its border). Disabled
    /// mid preparation so two picks can't overlap.
    private var addMoreButton: some View {
        UploadSourceMenu(
            label: { UploadDashedLabel(title: L10n.Uploads.reviewAddMore) },
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .tint(.primaryDS)
        .disabled(store.isPreparing)
        .opacity(store.isPreparing ? Constants.disabledOpacity : Constants.enabledOpacity)
    }

    private var isConfirmingCancel: Binding<Bool> {
        // Alerts have no tap outside dismissal, so this alert only ever closes through one of
        // its own buttons, and each button resets the flag through the reducer. A no op setter
        // keeps SwiftUI from firing a second dismiss action into an already torn down
        // presentation once "Discard" nils the whole feature.
        Binding(get: { store.isConfirmingCancel }, set: { _ in })
    }

    private var title: String {
        store.totalCount == 1
            ? L10n.Uploads.reviewTitleOne
            : L10n.Uploads.reviewTitleMany(store.totalCount)
    }

    /// `http` server: reachable only where the box is (typically the user's LAN), so an
    /// upload started away from that network just fails. The plaintext-security angle is
    /// already covered on the login screen; this is the "won't work from the coffee shop" heads-up.
    private var isServerConnectionInsecure: Bool {
        store.serverURL.scheme?.lowercased() == "http"
    }

    /// The whole sheet as one measured stack (header, the destination + size rows, the file
    /// list, then the two buttons) so `DSDynamicHeightSheet` sizes to exactly this — no
    /// per-piece height guesses.
    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: IconKit.upload,
                title: title,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: { store.send(.cancelTapped) }
            )
            if isServerConnectionInsecure {
                DSInfoCard(L10n.Uploads.reviewInsecureNetworkNotice)
            }
            if store.skippedCount > 0 {
                DSInfoCard(L10n.Uploads.stagingSkipped(store.skippedCount))
            }
            pathAndSizeSection
            filesSection
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.verticalPadding)
        .padding(.bottom, Constants.contentSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pinned below the scrolling list so Upload is always reachable, however many files.
    private var footer: some View {
        DSSheetFooter {
            VStack(spacing: Constants.rowSpacing) {
                addMoreButton
                DSButton(L10n.Uploads.reviewUploadButton, icon: IconKit.upload, style: .primary, isLoading: store.isPreparing) {
                    store.send(.uploadTapped)
                }
                .disabled(!store.canUpload)
            }
        }
    }

    private func infoRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Constants.rowSpacing, content: content)
            .contentShape(Rectangle())
    }

    private var pathAndSizeSection: some View {
        VStack(spacing: Constants.sectionRowSpacing) {
            Button { store.send(.pathTapped) } label: {
                infoRow {
                    rowIcon(IconKit.folder)
                    Text(L10n.Uploads.reviewSectionPath)
                        .type(.body2(.regular), style: .primary(for: .label))
                    Spacer()
                    Text(store.hasDestination
                        ? (store.destination as NSString).lastPathComponent
                        : L10n.Uploads.reviewChooseFolder)
                        .type(.body2(.regular), style: .secondary)
                        .lineLimit(1)
                    IconKit.chevronRight
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: .iconXSmall, height: .iconXSmall)
                }
            }
            .buttonStyle(DSHapticButtonStyle())
            .tint(.primaryDS)

            Divider()

            infoRow {
                rowIcon(IconKit.size)
                Text(L10n.Uploads.reviewSectionSize)
                    .type(.body2(.regular), style: .primary(for: .label))
                Spacer()
                Text(UploadReviewFormat.byteFormatter.string(fromByteCount: store.totalSize))
                    .type(.body2(.regular), style: .secondary)
            }
        }
        .padding(.vertical, Constants.cellVerticalPadding)
        .padding(.horizontal, Constants.cellHorizontalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard))
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Constants.rowSpacing) {
            DSFieldLabel(L10n.Uploads.reviewSectionFiles)
            ForEach(Array(store.files.enumerated()), id: \.element.id) { index, file in
                UploadFileRow(
                    file: file,
                    onPreview: { previewSelection = PreviewSelection(id: file.id) },
                    onRemove: { store.send(.removeFileTapped(id: file.id), animation: .default) }
                )
                if index < store.files.count - 1 {
                    Divider()
                }
            }
            if store.isPreparing {
                HStack(spacing: Constants.rowSpacing) {
                    DSSpinner()
                    Text(L10n.Uploads.reviewPreparing(store.preparingCount))
                        .type(.body3(.regular), style: .secondary)
                }
                .padding(.vertical, .space4)
            }
            if store.stagingFailed, store.files.isEmpty {
                HStack(spacing: Constants.rowTextSpacing * 2) {
                    IconKit.warning
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.negative)
                        .frame(width: .iconXSmall, height: .iconXSmall)
                    Text(L10n.Uploads.stagingFailed)
                        .type(.body3(.semibold), style: .error)
                }
            }
        }
        .padding(.top, .space8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            content
        } footer: {
            footer
        }
        .interactiveDismissDisabled(!store.files.isEmpty || store.isPreparing)
        .sheet(isPresented: isConfirmingCancel) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: L10n.Uploads.discardTitle,
                message: L10n.Uploads.discardMessage,
                confirmTitle: L10n.Uploads.discardConfirm,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.confirmCancelTapped) },
                onDismiss: { store.send(.cancelConfirmationDismissed) }
            )
        }
        .sheet(item: $store.scope(state: \.folderPicker, action: \.folderPicker)) { pickerStore in
            DestinationPickerView(store: pickerStore)
        }
        .fullScreenCover(item: $previewSelection) { selection in
            PickedFilePreview(
                urls: store.files.map(\.fileURL),
                names: store.files.map(\.fileName),
                initialIndex: store.files.firstIndex(where: { $0.id == selection.id }) ?? 0,
                onClose: { previewSelection = nil }
            )
        }
        .modifier(UploadPickers(
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented,
            photosSelection: $photosSelection,
            onDocumentsPicked: { urls in
                guard !urls.isEmpty else { return }
                store.send(.stage(.documents(urls)))
            },
            onPhotosPicked: { items in
                guard !items.isEmpty else { return }
                store.send(.stage(.photos(items)))
                photosSelection = []
            },
            onCameraCaptured: { url in
                store.send(.stage(.camera(url)))
            }
        ))
    }
}

private func previewFile(_ name: String, size: Int64) -> PickedFile {
    PickedFile(fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: size)
}

#Preview("Ready") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UploadReviewView(
            store: Store(
                initialState: UploadReviewFeature.State(
                    serverURL: URL(string: "https://example.com")!,
                    files: [
                        previewFile("beach.jpg", size: 2_400_000),
                        previewFile("itinerary.pdf", size: 180_000),
                        previewFile("notes.txt", size: 1_200),
                    ],
                    startingDestination: "Documents/Trips"
                )
            ) { UploadReviewFeature() }
        )
    }
}

#Preview("Preparing") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UploadReviewView(
            store: Store(
                initialState: UploadReviewFeature.State(
                    serverURL: URL(string: "https://example.com")!,
                    startingDestination: "",
                    preparingCount: 3
                )
            ) { UploadReviewFeature() }
        )
    }
}

#Preview("All failed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UploadReviewView(
            store: Store(
                initialState: {
                    var state = UploadReviewFeature.State(
                        serverURL: URL(string: "https://example.com")!,
                        startingDestination: "Documents"
                    )
                    state.stagingFailed = true
                    return state
                }()
            ) { UploadReviewFeature() }
        )
    }
}

#Preview("HTTP server notice") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UploadReviewView(
            store: Store(
                initialState: UploadReviewFeature.State(
                    serverURL: URL(string: "http://192.168.1.50:3000")!,
                    files: [
                        previewFile("beach.jpg", size: 2_400_000),
                        previewFile("notes.txt", size: 1_200),
                    ],
                    startingDestination: "Documents/Trips"
                )
            ) { UploadReviewFeature() }
        )
    }
}
