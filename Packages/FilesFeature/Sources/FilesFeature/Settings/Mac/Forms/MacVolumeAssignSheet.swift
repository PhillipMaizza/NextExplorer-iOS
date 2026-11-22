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
        @State private var browseAttempt = 0

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
                    MacTextField(L10n.UserDetail.volumeSheetLabelField, text: Binding(
                        get: { store.volumeSheet?.label ?? "" },
                        set: { store.send(.volumeLabelChanged($0)) }
                    ), prompt: L10n.UserDetail.volumeSheetLabelPlaceholder)
                        .autocorrectionDisabled()
                }
                MacSettingsRow(L10n.UserDetail.volumeSheetAccessMode) {
                    MacSegmentedPicker(
                        L10n.UserDetail.volumeSheetAccessMode,
                        options: ShareAccessMode.allCases,
                        selection: Binding(
                            get: { store.volumeSheet?.accessMode ?? .readwrite },
                            set: { store.send(.volumeAccessModeChanged($0)) }
                        )
                    ) { $0.title }
                }
                MacSettingsRow(L10n.UserDetail.volumeSheetDirectory) {
                    if isEditing {
                        Text(sheet?.selectedPath ?? "")
                            .monospaced()
                            .foregroundStyle(Color.macChromeSecondary)
                            .textSelection(.enabled)
                    } else {
                        browser(selectedPath: sheet?.selectedPath ?? "")
                    }
                }
            }
            .task(id: BrowseRequest(path: browsePath, attempt: browseAttempt)) {
                guard store.volumeSheet?.isEditing == false else { return }
                await loadDirectories(path: browsePath)
            }
        }

        private func browser(selectedPath: String) -> some View {
            VStack(spacing: .zero) {
                HStack(spacing: .space8) {
                    Button { browsePath = listing?.parent } label: {
                        IconKit.back.foregroundStyle(Color.macChromeSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(listing?.parent == nil)
                    .accessibilityLabelWithTooltip(L10n.UserDetail.directoryPickerGoUp)
                    Text(listing?.current ?? "")
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: .zero)
                }
                .macListRow(isSelected: false)
                hairline
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        ForEach(listing?.directories ?? [], id: \.path) { directory in
                            directoryRow(directory, isSelected: directory.path == selectedPath)
                        }
                        if let browseError = browsePhase.errorMessage {
                            HStack {
                                Text(browseError).foregroundStyle(Color.negativeText)
                                Spacer(minLength: .zero)
                                Button(L10n.Common.retry) { browseAttempt += 1 }
                                    .buttonStyle(.macDS(.secondary, size: .small))
                            }
                            .macListRow(isSelected: false)
                        }
                    }
                }
                .frame(height: Metrics.browserHeight)
                .overlay {
                    if browsePhase == .loading, listing == nil {
                        MacSpinner()
                    }
                }
                hairline
                HStack {
                    Spacer(minLength: .zero)
                    if let current = listing?.current {
                        Button(L10n.UserDetail.directoryPickerUseThis) { store.send(.volumePathSelected(current)) }
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                }
                .padding(.vertical, .space8)
                .macListRow(isSelected: false)
            }
            .macListBox()
        }

        private var hairline: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
        }

        private func directoryRow(_ directory: AdminDirectory, isSelected: Bool) -> some View {
            HStack(spacing: .space8) {
                MacItemIcon(kind: "", isDirectory: true)
                Text(directory.name).lineLimit(1)
                Spacer(minLength: .zero)
                IconKit.chevronRight
                    .imageScale(.small)
                    .foregroundStyle(Color.macChromeSecondary)
            }
            .foregroundStyle(Color.macChromeText)
            .macListRow(isSelected: isSelected)
            .onTapGesture(count: 2) { browsePath = directory.path }
            .onTapGesture { store.send(.volumePathSelected(directory.path)) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { store.send(.volumePathSelected(directory.path)) }
            .accessibilityAction(named: L10n.UserDetail.directoryPickerOpen(directory.name)) {
                browsePath = directory.path
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
                let message = (error as? FilesClientError)?.userMessage
                browsePhase = .failed(message ?? L10n.UserDetail.directoryPickerFailed)
            }
        }
    }

    private struct BrowseRequest: Hashable {
        let path: String?
        let attempt: Int
    }

    @MainActor
    private func volumeSheetPreview(editing volumeID: String? = nil, error: String? = nil) -> some View {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
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
