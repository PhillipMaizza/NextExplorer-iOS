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
    static let contentSpacing: CGFloat = .space16
    static let rowSpacing: CGFloat = .space12
    static let rowTextSpacing: CGFloat = .space2
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space24
    static let closeButtonPadding: CGFloat = .space8
    static let addMoreDash: CGFloat = 4
    static let addMoreBorderWidth: CGFloat = 1
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
            thumbnail(for: file)
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
    }

    @ViewBuilder
    private func thumbnail(for file: PickedFile) -> some View {
        let kind = (file.fileName as NSString).pathExtension.lowercased()
        if FileItem.isImageKind(kind), kind != "svg" {
            AsyncImage(url: file.fileURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.backgroundSecondary
                }
            }
            .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
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
            header
            pathAndSizeSection
            Divider()
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

    private var header: some View {
        HStack {
            Text(title).type(.headline3, style: .link)
            Spacer()
            Button { store.send(.cancelTapped) } label: {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: .iconXSmall, height: .iconXSmall)
                    .padding(Constants.closeButtonPadding)
                    .background(Circle().fill(Color.backgroundSecondary))
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Common.close)
        }
    }

    private var pathAndSizeSection: some View {
        VStack(spacing: Constants.rowSpacing) {
            Button { store.send(.pathTapped) } label: {
                HStack(spacing: Constants.rowSpacing) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(DSHapticButtonStyle())
            .tint(.primaryDS)

            HStack(spacing: Constants.rowSpacing) {
                rowIcon(IconKit.size)
                Text(L10n.Uploads.reviewSectionSize)
                    .type(.body2(.regular), style: .primary(for: .label))
                Spacer()
                Text(Self.byteFormatter.string(fromByteCount: store.totalSize))
                    .type(.body2(.regular), style: .secondary)
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Constants.rowSpacing) {
            Text(L10n.Uploads.reviewSectionFiles)
                .type(.body3(.semibold), style: .secondary)
            ForEach(store.files) { file in
                fileRow(file)
            }
            if store.isPreparing {
                HStack(spacing: Constants.rowSpacing) {
                    ProgressView()
                    Text(L10n.Uploads.reviewPreparing(store.preparingCount))
                        .type(.body3(.regular), style: .secondary)
                }
            }
            if store.stagingFailed, store.files.isEmpty {
                Text(L10n.Uploads.stagingFailed)
                    .type(.body3(.regular), style: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        DynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            content
        } footer: {
            footer
        }
        .sheet(item: $store.scope(state: \.folderPicker, action: \.folderPicker)) { pickerStore in
            DestinationPickerView(store: pickerStore)
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
            onPhotoCaptured: { url in
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
