#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 560
        static let tableHeight: CGFloat = 220
        static let sizeColumnWidth: CGFloat = 90
    }

    /// The upload review as a native Mac dialog: where the files go and how big they are, the
    /// files in a table (remove with the minus button or Delete), then Add Files…, Cancel and
    /// Upload.
    struct MacUploadReviewSheet: View {
        let store: StoreOf<UploadReviewFeature>
        let title: String
        let isServerConnectionInsecure: Bool
        let onAddFiles: () -> Void
        @State private var selection: Set<PickedFile.ID> = []

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                Text(title).font(.headline)
                if isServerConnectionInsecure {
                    notice(L10n.Uploads.reviewInsecureNetworkNotice)
                }
                if store.skippedCount > 0 {
                    notice(L10n.Uploads.stagingSkipped(store.skippedCount))
                }
                Form {
                    MacSettingsRow(L10n.Uploads.reviewSectionPath) {
                        HStack {
                            Text(store.hasDestination ? store.destination : L10n.Uploads.reviewChooseFolder)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(store.hasDestination ? .primary : .secondary)
                            Spacer()
                            Button(L10n.MacSettings.choose) { store.send(.pathTapped) }
                        }
                    }
                    MacSettingsRow(L10n.Uploads.reviewSectionSize) {
                        Text(FileSizeFormat.string(store.totalSize))
                            .monospacedDigit()
                    }
                }
                .formStyle(.columns)
                VStack(spacing: 0) {
                    filesTable
                    Divider()
                    HStack(spacing: 0) {
                        MacTableBarButton(icon: IconKit.plus, label: L10n.Uploads.reviewAddMore) { onAddFiles() }
                            .disabled(store.isPreparing)
                        MacTableBarDivider()
                        MacTableBarButton(icon: IconKit.minus, label: L10n.Common.remove) { removeSelection() }
                            .disabled(selection.isEmpty)
                        Spacer()
                        if store.isPreparing {
                            MacSpinner()
                            Text(L10n.Uploads.reviewPreparing(store.preparingCount))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, .space8)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, .space4)
                    .padding(.vertical, .space2)
                }
                .border(Color(nsColor: .separatorColor))
                if store.stagingFailed, store.files.isEmpty {
                    Text(L10n.Uploads.stagingFailed).foregroundStyle(Color.negativeText)
                }
                MacDialogButtons(
                    confirmTitle: L10n.Uploads.reviewUploadButton,
                    isConfirmEnabled: store.canUpload,
                    onCancel: { store.send(.cancelTapped) },
                    onConfirm: { store.send(.uploadTapped) }
                )
            }
            .padding(.space24)
            .frame(width: Metrics.width)
        }

        private var filesTable: some View {
            Table(store.files, selection: $selection) {
                TableColumn(L10n.Sort.name) { file in
                    Label {
                        Text(file.fileName).lineLimit(1).truncationMode(.middle)
                    } icon: {
                        Image(nsImage: MacFileTypeIcon.image(forFileName: file.fileName))
                            .resizable()
                            .frame(width: .iconSmall, height: .iconSmall)
                            .accessibilityHidden(true)
                    }
                }
                TableColumn(L10n.Sort.size) { file in
                    Text(FileSizeFormat.string(file.size))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: PickedFile.ID.self) { ids in
                Button(role: .destructive) { remove(ids) } label: {
                    Label { Text(L10n.Common.remove) } icon: { IconKit.delete }
                }
                .labelStyle(.titleAndIcon)
            }
            .onDeleteCommand { removeSelection() }
            .frame(height: Metrics.tableHeight)
        }

        private func notice(_ text: String) -> some View {
            Label { Text(text) } icon: { IconKit.warning }
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        private func removeSelection() {
            remove(selection)
            selection = []
        }

        private func remove(_ ids: Set<PickedFile.ID>) {
            for id in ids {
                store.send(.removeFileTapped(id: id), animation: .default)
            }
        }
    }

    @MainActor
    private func uploadReviewPreview(_ state: UploadReviewFeature.State, isInsecure: Bool = false) -> some View {
        MacUploadReviewSheet(
            store: Store(initialState: state) { UploadReviewFeature() },
            title: "Upload 3 Items",
            isServerConnectionInsecure: isInsecure,
            onAddFiles: {}
        )
    }

    #Preview("Ready") {
        uploadReviewPreview(UploadReviewFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            files: [
                PickedFile(fileURL: URL(fileURLWithPath: "/tmp/beach.jpg"), fileName: "beach.jpg", size: 2_400_000),
                PickedFile(fileURL: URL(fileURLWithPath: "/tmp/itinerary.pdf"), fileName: "itinerary.pdf", size: 180_000),
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
