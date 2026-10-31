#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
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
        @State private var browsePhase: DataPhase = .idle
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
                    Button { browsePath = listing?.parent } label: { IconKit.back }
                        .disabled(listing?.parent == nil)
                        .accessibilityLabelWithTooltip(L10n.UserDetail.directoryPickerGoUp)
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
                        Label { Text(directory.name) } icon: { IconKit.folder }.tag(directory.path)
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
                    if browsePhase == .loading, listing == nil {
                        MacSpinner()
                    } else if let browseError = browsePhase.errorMessage {
                        Text(browseError).foregroundStyle(.secondary).padding()
                    }
                }
            }
        }

        private func loadDirectories(path: String?) async {
            browsePhase = .loading
            do {
                let next = try await filesClient.browseAdminDirectories(store.serverURL, path)
                guard !Task.isCancelled else { return }
                listing = next
                browsePhase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                browsePhase = .failed((error as? FilesClientError)?.userMessage ?? L10n.UserDetail.directoryPickerFailed)
            }
        }
    }

    @MainActor
    private func volumeSheetPreview(editing volumeID: String? = nil, error: String? = nil) -> some View {
        var state = UserManagementFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), currentUserID: "u1")
        var sheet = UserManagementFeature.VolumeSheetState(userID: "u2", editingVolumeID: volumeID)
        sheet.label = volumeID == nil ? "" : "Media"
        sheet.selectedPath = volumeID == nil ? "" : "/mnt/media"
        sheet.errorMessage = error
        state.volumeSheet = sheet
        return MacVolumeAssignSheet(store: Store(initialState: state) { UserManagementFeature() })
            .dependency(\.filesClient, .previewValue)
    }

    #Preview("Assign") {
        volumeSheetPreview()
    }

    #Preview("Edit") {
        volumeSheetPreview(editing: "v1")
    }

    #Preview("Error") {
        volumeSheetPreview(editing: "v1", error: "The folder no longer exists.")
    }
#endif
