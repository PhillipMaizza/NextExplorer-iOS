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
                        Text(UploadReviewFormat.byteFormatter.string(fromByteCount: store.totalSize))
                            .monospacedDigit()
                    }
                }
                .formStyle(.columns)
                VStack(spacing: 0) {
                    filesTable
                    Divider()
                    HStack(spacing: 0) {
                        Button { onAddFiles() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                            .disabled(store.isPreparing)
                            .accessibilityLabel(L10n.Uploads.reviewAddMore)
                        Divider().frame(height: 16)
                        Button { removeSelection() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                            .disabled(selection.isEmpty)
                            .accessibilityLabel(L10n.Common.remove)
                        Spacer()
                        if store.isPreparing {
                            ProgressView().controlSize(.small)
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
                HStack {
                    Spacer()
                    Button(L10n.Common.cancel) { store.send(.cancelTapped) }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.Uploads.reviewUploadButton) { store.send(.uploadTapped) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!store.canUpload)
                }
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
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.fileURL.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                TableColumn(L10n.Sort.size) { file in
                    Text(UploadReviewFormat.byteFormatter.string(fromByteCount: file.size))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: PickedFile.ID.self) { ids in
                Button(L10n.Common.remove, role: .destructive) { remove(ids) }
            }
            .onDeleteCommand { removeSelection() }
            .frame(height: Metrics.tableHeight)
        }

        private func notice(_ text: String) -> some View {
            Label(text, systemImage: "exclamationmark.triangle")
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
#endif
