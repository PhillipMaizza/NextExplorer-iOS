#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let searchWidth: CGFloat = 260
    }

    struct MacVersionedFilesPane: View {
        @Bindable var store: StoreOf<VersionedFilesFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: false,
                unavailableMessage: L10n.VersionedFiles.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.page == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                summary
                filters
                MacVersionedFilesTable(store: store)
                if let error = store.listError {
                    MacNote(error, kind: .error)
                }
                ForEach(store.files.filter { store.expanded.contains($0.id) }) { file in
                    MacVersionedFileDetail(store: store, file: file)
                        .transition(.opacity)
                }
                pager
            }
            .versionedFilesDeleteAlert(store)
        }

        @ViewBuilder
        private var summary: some View {
            if let page = store.page {
                HStack(spacing: .space4) {
                    Text(L10n.VersionedFiles.summary(
                        page.total,
                        page.totalVersions,
                        TrashSettingsView.bytes(page.totalBytes)
                    ))
                    .type(.body2(.regular), style: .secondary)
                    MacInfoButton(L10n.VersionedFiles.subtitle)
                }
            }
        }

        private var filters: some View {
            HStack(spacing: .space8) {
                MacTextField(
                    L10n.VersionedFiles.searchPlaceholder,
                    text: $store.filter.query.sending(\.queryChanged),
                    prompt: L10n.VersionedFiles.searchPlaceholder
                )
                .autocorrectionDisabled()
                .onSubmit { store.send(.searchSubmitted) }
                .frame(width: Metrics.searchWidth)
                if let zones = store.page?.zones, !zones.isEmpty {
                    MacPopup(
                        L10n.VersionedFiles.zone,
                        valueLabel: zones.first { $0.id == store.filter.zoneID }
                            .map(VersionedFileWords.zone) ?? L10n.VersionedFiles.anyZone,
                        selection: $store.filter.zoneID.sending(\.zoneFilterChanged)
                    ) {
                        Text(L10n.VersionedFiles.anyZone).tag(String?.none)
                        ForEach(zones) { zone in
                            Text(VersionedFileWords.zone(zone)).tag(String?.some(zone.id))
                        }
                    }
                }
                MacPopup(
                    L10n.VersionedFiles.stateHeader,
                    valueLabel: VersionedFileWords.state(store.filter.state),
                    selection: $store.filter.state.sending(\.stateFilterChanged)
                ) {
                    Text(L10n.VersionedFiles.anyState).tag(VersionedFileState?.none)
                    ForEach(VersionedFileState.allCases, id: \.self) { state in
                        Text(VersionedFileWords.state(state)).tag(VersionedFileState?.some(state))
                    }
                }
                MacPopup(
                    L10n.VersionedFiles.sortHeader,
                    valueLabel: VersionedFileWords.sort(store.filter.sort),
                    selection: $store.filter.sort.sending(\.sortChanged)
                ) {
                    ForEach(VersionedFileSort.allCases, id: \.self) { sort in
                        Text(VersionedFileWords.sort(sort)).tag(sort)
                    }
                }
            }
            .disabled(store.isFilterDisabled)
        }

        @ViewBuilder
        private var pager: some View {
            if let page = store.page, page.total > 0 {
                HStack(spacing: .space8) {
                    Text(L10n.VersionedFiles.pageRange(page.firstShown, page.lastShown, page.total))
                        .type(.body2(.regular), style: .secondary)
                    Spacer(minLength: .zero)
                    Button(L10n.VersionedFiles.previous) { store.send(.previousPageTapped) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(!page.hasPrevious || store.isReloading)
                    Button(L10n.VersionedFiles.next) { store.send(.nextPageTapped) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(!page.hasNext || store.isReloading)
                }
            }
        }
    }

    private struct MacVersionedFileDetail: View {
        let store: StoreOf<VersionedFilesFeature>
        let file: VersionedFile

        private var selectedCount: Int {
            store.selection[file.id]?.count ?? 0
        }

        var body: some View {
            MacFormGroup {
                MacFormRow {
                    MacFormRowTitle(
                        title: file.name,
                        subtitle: ServerSettingsMetrics.joined(
                            [VersionedFileWords.zone(file.zone), file.folder].filter { !$0.isEmpty }
                        )
                    )
                } control: {
                    HStack(spacing: .space8) {
                        Button(selectedCount == 0
                            ? L10n.VersionedFiles.deleteSelectedNone
                            : L10n.VersionedFiles.deleteSelected(selectedCount))
                        {
                            store.send(.deleteSelectedTapped(fileID: file.id))
                        }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(selectedCount == 0 || store.isWorking)
                        Button(L10n.VersionedFiles.deleteAll, role: .destructive) {
                            store.send(.deleteAllTapped(fileID: file.id))
                        }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(store.isWorking)
                    }
                }
                if let message = store.detailErrors[file.id] {
                    MacFormRow {
                        MacNote(message, kind: .error)
                    } control: {
                        EmptyView()
                    }
                } else if let detail = store.details[file.id] {
                    ForEach(detail.versions) { version in
                        versionRow(version)
                    }
                } else {
                    MacFormRow {
                        MacSpinner()
                    } control: {
                        EmptyView()
                    }
                }
            }
        }

        private func versionRow(_ version: FileVersion) -> some View {
            MacFormRow {
                Toggle(isOn: Binding(
                    get: { store.selection[file.id]?.contains(version.id) ?? false },
                    set: { _ in store.send(.versionToggled(fileID: file.id, versionID: version.id)) }
                )) {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(version.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        if let subtitle = VersionedFileWords.subtitle(version) {
                            Text(subtitle).type(.body3(.regular), style: .secondary)
                        }
                    }
                }
                .toggleStyle(.macCheckbox)
            } control: {
                Text(TrashSettingsView.bytes(Int(version.size)))
                    .foregroundStyle(Color.macChromeSecondary)
                    .monospacedDigit()
            }
        }
    }

    #Preview("Files with history") {
        var state = VersionedFilesFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.page = PreviewVersions.page
        state.phase = .loaded
        state.expanded = ["f1"]
        state.details = ["f1": PreviewVersions.detail]
        return MacVersionedFilesPane(store: Store(initialState: state) { EmptyReducer() })
            .previewCanvas(.settingsWindow)
            .background(Color.macCard)
    }

    #Preview("Empty") {
        var state = VersionedFilesFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.page = VersionedFilesPage()
        state.phase = .loaded
        return MacVersionedFilesPane(store: Store(initialState: state) { EmptyReducer() })
            .previewCanvas(.window)
            .background(Color.macCard)
    }
#endif
