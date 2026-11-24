#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listHeight: CGFloat = 168
        static let tileSize: CGFloat = 22
        static let rowHeight: CGFloat = .size32
    }

    /// The upload review as a Mac sheet: where the files go and their total size, the files in a
    /// list box (each with its remove button), Add more files, then Cancel and Upload.
    struct MacUploadReviewSheet: View {
        let store: StoreOf<UploadReviewFeature>
        let title: String
        let isServerConnectionInsecure: Bool
        let onAddFiles: () -> Void

        var body: some View {
            MacFormSheet(
                title: title,
                confirmTitle: L10n.Uploads.reviewUploadButton,
                isConfirmEnabled: store.canUpload,
                errorMessage: store.hasStagingFailed && store.files.isEmpty ? L10n.Uploads.stagingFailed : nil,
                onCancel: { store.send(.cancelTapped) },
                onConfirm: { store.send(.uploadTapped) }
            ) {
                MacSettingsRow(L10n.Uploads.reviewSectionPath) {
                    MacPathField(
                        path: store.hasDestination ? PersonalSpace.trail(store.destination) : nil,
                        placeholder: L10n.Uploads.reviewChooseFolder
                    ) { store.send(.pathTapped) }
                }
                MacSettingsRow(L10n.Uploads.reviewSectionSize) {
                    Text(FileSizeFormat.string(store.totalSize)).monospacedDigit()
                }
                MacSettingsRow(L10n.Uploads.reviewSectionFiles) {
                    filesBox
                    Button(L10n.Uploads.reviewAddMore, action: onAddFiles)
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(store.isPreparing)
                }
            } below: {
                if isServerConnectionInsecure {
                    hint(L10n.Uploads.reviewInsecureNetworkNotice)
                }
                if store.skippedCount > 0 {
                    hint(L10n.Uploads.stagingSkipped(store.skippedCount))
                        .macDialogReveal()
                }
            }
        }

        private var filesBox: some View {
            VStack(spacing: .zero) {
                HStack {
                    Text(L10n.Sort.name)
                    Spacer(minLength: .space8)
                    Text(L10n.Sort.size)
                }
                .type(.caption(.semibold), style: .secondary)
                .macListRow(isSelected: false)
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        ForEach(store.files) { file in
                            fileRow(file)
                        }
                        if store.isPreparing {
                            HStack(spacing: .space8) {
                                DSSpinner(size: .small)
                                Text(L10n.Uploads.reviewPreparing(store.preparingCount))
                                    .type(.body2(.regular), style: .secondary)
                                Spacer(minLength: .zero)
                            }
                            .macListRow(isSelected: false)
                            .macDialogReveal()
                        }
                    }
                    .animation(DSMotion.stateFade, value: store.files.count)
                }
            }
            .frame(height: Metrics.listHeight, alignment: .top)
            .macListBox()
        }

        private func fileRow(_ file: PickedFile) -> some View {
            HStack(spacing: .space8) {
                MacItemTile(
                    kind: (file.fileName as NSString).pathExtension.lowercased(),
                    isDirectory: false,
                    size: Metrics.tileSize
                )
                Text(file.fileName)
                    .type(.body2(.regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: .space8)
                Text(FileSizeFormat.string(file.size))
                    .type(.body3(.regular), style: .secondary)
                    .monospacedDigit()
                MacRowRemoveButton(label: L10n.Common.remove) {
                    store.send(.removeFileTapped(id: file.id), animation: DSMotion.listDiff)
                }
            }
            .foregroundStyle(Color.macChromeText)
            .frame(minHeight: Metrics.rowHeight)
            .macListRow(isSelected: false)
        }

        private func hint(_ text: String) -> some View {
            Text(text)
                .type(.body3(.regular), style: .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func uploadReviewPreview(_ state: UploadReviewFeature.State, isInsecure: Bool = false) -> some View {
        MacUploadReviewSheet(
            store: Store(initialState: state) { UploadReviewFeature() },
            title: "Upload 3 files",
            isServerConnectionInsecure: isInsecure,
            onAddFiles: {}
        )
    }

    #Preview("Ready") {
        uploadReviewPreview(UploadReviewFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            files: [
                PickedFile(fileURL: URL(fileURLWithPath: "/tmp/beach.jpg"), fileName: "beach.jpg", size: 2_400_000),
                PickedFile(
                    fileURL: URL(fileURLWithPath: "/tmp/itinerary.pdf"),
                    fileName: "itinerary.pdf",
                    size: 180_000
                ),
            ],
            startingDestination: "Documents/Trips"
        ))
    }

    #Preview("Preparing") {
        uploadReviewPreview(UploadReviewFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            startingDestination: "",
            preparingCount: 3
        ))
    }

    #Preview("Insecure server") {
        uploadReviewPreview(UploadReviewFeature.State(
            serverURL: URL(string: "http://192.168.1.10") ?? URL(fileURLWithPath: "/"),
            files: [PickedFile(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"), fileName: "notes.txt", size: 1_200)],
            startingDestination: "Documents"
        ), isInsecure: true)
    }
#endif
