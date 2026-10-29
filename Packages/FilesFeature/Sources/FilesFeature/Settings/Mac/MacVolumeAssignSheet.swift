#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 560
        static let browserHeight: CGFloat = 220
    }

    /// Assign or edit a user volume as a native sheet: a label, the access mode, and for a new
    /// volume a folder browser on the server (click to choose, double click to open).
    struct MacVolumeAssignSheet: View {
        let store: StoreOf<UserManagementFeature>
        @Dependency(\.filesClient) private var filesClient

        @State private var listing: AdminDirectoryListing?
        @State private var isBrowsing = false
        @State private var browseError: String?
        /// The folder being listed; `nil` is the server's volume root. A `.task(id:)` key, so
        /// opening folders quickly cancels the listing before the next.
        @State private var browsePath: String?

        var body: some View {
            let sheet = store.volumeSheet
            let isEditing = sheet?.isEditing ?? false
            MacFormSheet(
                title: isEditing ? L10n.UserDetail.volumeSheetTitleEdit : L10n.UserDetail.volumeSheetTitleNew,
                confirmTitle: isEditing ? L10n.UserDetail.volumeSheetSaveEdit : L10n.UserDetail.volumeSheetSaveNew,
                isConfirmEnabled: sheet?.isSubmitEnabled ?? false,
                isWorking: sheet?.isSubmitting ?? false,
                errorMessage: sheet?.errorMessage,
                width: Metrics.width,
                onCancel: { store.send(.volumeSheetDismissed) },
                onConfirm: { store.send(.volumeSubmitTapped) }
            ) {
                MacSettingsRow(L10n.UserDetail.volumeSheetLabelField) {
                    TextField(L10n.UserDetail.volumeSheetLabelField, text: Binding(
                        get: { store.volumeSheet?.label ?? "" },
                        set: { store.send(.volumeLabelChanged($0)) }
                    ), prompt: Text(L10n.UserDetail.volumeSheetLabelPlaceholder))
                        .labelsHidden()
                        .autocorrectionDisabled()
                }
                MacSettingsRow(L10n.UserDetail.volumeSheetAccessMode) {
                    Picker(L10n.UserDetail.volumeSheetAccessMode, selection: Binding(
                        get: { store.volumeSheet?.accessMode ?? .readwrite },
                        set: { store.send(.volumeAccessModeChanged($0)) }
                    )) {
                        ForEach(ShareAccessMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                MacSettingsRow(L10n.UserDetail.volumeSheetDirectory) {
                    if isEditing {
                        Text(sheet?.selectedPath ?? "").foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        browser(selectedPath: sheet?.selectedPath ?? "")
                    }
                }
            }
            .task(id: browsePath) {
                guard store.volumeSheet?.isEditing == false else { return }
                await loadDirectories(path: browsePath)
            }
        }

        private func browser(selectedPath: String) -> some View {
            VStack(alignment: .leading, spacing: .space4) {
                HStack {
                    Button { browsePath = listing?.parent } label: { Image(systemName: "chevron.left") }
                        .disabled(listing?.parent == nil)
                        .accessibilityLabel(L10n.UserDetail.directoryPickerGoUp)
                    Text(listing?.current ?? "")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let current = listing?.current {
                        Button(L10n.UserDetail.directoryPickerUseThis) { store.send(.volumePathSelected(current)) }
                    }
                }
                List(selection: Binding(get: { selectedPath.isEmpty ? nil : selectedPath }, set: { path in
                    if let path {
                        store.send(.volumePathSelected(path))
                    }
                })) {
                    ForEach(listing?.directories ?? [], id: \.path) { directory in
                        Label(directory.name, systemImage: "folder").tag(directory.path)
                    }
                }
                .contextMenu(forSelectionType: String.self, menu: { _ in }, primaryAction: { paths in
                    if let path = paths.first {
                        browsePath = path
                    }
                })
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: Metrics.browserHeight)
                .overlay {
                    if isBrowsing, listing == nil {
                        ProgressView()
                    } else if let browseError {
                        Text(browseError).foregroundStyle(.secondary).padding()
                    }
                }
            }
        }

        private func loadDirectories(path: String?) async {
            isBrowsing = true
            browseError = nil
            defer { isBrowsing = false }
            do {
                let next = try await filesClient.browseAdminDirectories(store.serverURL, path)
                guard !Task.isCancelled else { return }
                listing = next
            } catch {
                guard !Task.isCancelled else { return }
                browseError = (error as? FilesClientError)?.userMessage ?? L10n.UserDetail.directoryPickerFailed
            }
        }
    }
#endif
