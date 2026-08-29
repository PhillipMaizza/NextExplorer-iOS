import ComposableArchitecture
import CoreModels
import DesignSystem
import Foundation
import Localization
import PhotosUI
import SwiftUI

private enum Constants {
    static let thumbnailSize: CGFloat = .iconLarge
    static let removeButtonSize: CGFloat = .iconSmall
    static let contentSpacing: CGFloat = .space24
    static let sectionRowSpacing: CGFloat = .space16
    static let cellVerticalPadding: CGFloat = .space16
    static let cellHorizontalPadding: CGFloat = .space16
    static let rowSpacing: CGFloat = .space12
    static let rowTextSpacing: CGFloat = .space2
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let addMoreDash: CGFloat = 4
    static let addMoreBorderWidth: CGFloat = 1
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

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func rowIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.secondaryDS)
            .frame(width: .iconSmall, height: .iconSmall)
    }

    private func fileRow(_ file: PickedFile) -> some View {
        HStack(spacing: Constants.rowSpacing) {
            Button {
                previewSelection = PreviewSelection(id: file.id)
            } label: {
                thumbnail(for: file)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Uploads.reviewPreviewFile(file.fileName))
            VStack(alignment: .leading, spacing: Constants.rowTextSpacing) {
                Text(file.fileName)
                    .type(.body2(.regular), style: .primary(for: .label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.byteFormatter.string(fromByteCount: file.size))
                    .type(.body3(.regular), style: .secondary)
            }
            Spacer(minLength: Constants.rowSpacing)
            Button {
                store.send(.removeFileTapped(id: file.id), animation: .default)
            } label: {
                IconKit.closeCircle
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.removeButtonSize, height: Constants.removeButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.remove)
        }
        .padding(.vertical, .space4)
    }

    @ViewBuilder
    private func thumbnail(for file: PickedFile) -> some View {
        let kind = (file.fileName as NSString).pathExtension.lowercased()
        if FileItem.isImageKind(kind), kind != "svg" {
            AsyncImage(url: file.fileURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    FileTypeIcon(kind: kind)
                default:
                    ThumbnailLoadingPlaceholder()
                }
            }
            .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
        } else if FileItem.isVideoKind(kind) {
            VideoThumbnailView(url: file.fileURL, size: Constants.thumbnailSize)
        } else {
            FileTypeIcon(kind: kind)
                .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
        }
    }

    /// "Add more files" — opens the same camera / Photos / Files menu the browse `+` uses,
    /// streaming the new pick into this same sheet. A clear, dashed outline button that sits
    /// in the bottom bar above Upload (not a list cell, which would clip its border). Disabled
    /// mid preparation so two picks can't overlap.
    private var addMoreButton: some View {
        UploadSourceMenu(
            label: {
                HStack(spacing: Constants.rowTextSpacing * 2) {
                    IconKit.plus
                        .resizable().scaledToFit()
                        .frame(width: .iconSmall, height: .iconSmall)
                    Text(L10n.Uploads.reviewAddMore)
                        .type(.body2(.regular), style: .secondary)
                }
                .foregroundStyle(Color.secondaryDS)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.rowSpacing)
                .overlay(
                    RoundedRectangle(cornerRadius: .radiusControl)
                        .stroke(
                            Color.secondaryDS,
                            style: StrokeStyle(lineWidth: Constants.addMoreBorderWidth, dash: [Constants.addMoreDash])
                        )
                )
                .contentShape(Rectangle())
            },
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

    /// The whole sheet as one measured stack (header, the destination + size rows, the file
    /// list, then the two buttons) so `DynamicHeightSheet` sizes to exactly this — no
    /// per-piece height guesses.
    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: IconKit.upload,
                title: title,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: { store.send(.cancelTapped) }
            )
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
        VStack(spacing: Constants.rowSpacing) {
            addMoreButton
            DSButton(L10n.Uploads.reviewUploadButton, icon: IconKit.upload, style: .primary, isLoading: store.isPreparing) {
                store.send(.uploadTapped)
            }
            .disabled(!store.canUpload)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.bottom, Constants.verticalPadding)
        .background(Color.backgroundPrimary)
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
                Text(Self.byteFormatter.string(fromByteCount: store.totalSize))
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
                fileRow(file)
                if index < store.files.count - 1 {
                    Divider()
                }
            }
            if store.isPreparing {
                HStack(spacing: Constants.rowSpacing) {
                    ProgressView()
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
        DynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            content
        } footer: {
            footer
        }
        .interactiveDismissDisabled(!store.files.isEmpty || store.isPreparing)
        .alert(L10n.Uploads.discardTitle, isPresented: isConfirmingCancel) {
            Button(L10n.Uploads.discardConfirm, role: .destructive) { store.send(.confirmCancelTapped) }
            Button(L10n.Common.cancel, role: .cancel) { store.send(.cancelConfirmationDismissed) }
        } message: {
            Text(L10n.Uploads.discardMessage)
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

/// Full screen preview for a staged file, opened from its row thumbnail. Goes through
/// `QuickLook`, which swipes across the whole batch starting on the tapped file. Wrapped in a
/// `NavigationStack` so `previewChrome` can hang a close button off it — `QLPreviewController`
/// only draws its own Done bar when UIKit presents it directly, not through a representable.
private struct PickedFilePreview: View {
    let urls: [URL]
    let names: [String]
    let initialIndex: Int
    let onClose: () -> Void

    @State private var currentIndex: Int

    init(urls: [URL], names: [String], initialIndex: Int, onClose: @escaping () -> Void) {
        self.urls = urls
        self.names = names
        self.initialIndex = initialIndex
        self.onClose = onClose
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var title: String? {
        names.indices.contains(currentIndex) ? names[currentIndex] : nil
    }

    var body: some View {
        NavigationStack {
            QuickLookPreview(urls: urls, initialIndex: initialIndex) { currentIndex = $0 }
                .ignoresSafeArea()
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .previewChrome(title: title, onClose: onClose)
        }
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
