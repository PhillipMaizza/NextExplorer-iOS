import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let expandedChevronDegrees: Double = 180
}

/// Admin list of every file that has a history, pushed from the Settings admin section. Mirrors the
/// web client's `SettingsFileVersions.vue`.
struct VersionedFilesView: View {
    @Bindable var store: StoreOf<VersionedFilesFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.VersionedFiles.navigationTitle,
            subtitle: L10n.VersionedFiles.subtitle,
            unavailableMessage: L10n.VersionedFiles.unavailable,
            isUnavailable: false,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.listError,
            isLoadingFirstTime: store.phase == .loading && store.page == nil,
            onAppear: { store.send(.onAppear) }
        ) {
            summary
            filtersCard
            filesList
            pager
        }
        .dsAlert(isPresented: Binding(get: { store.confirmation != nil }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: confirmationTitle,
                message: L10n.VersionedFiles.confirmMessage,
                confirmTitle: L10n.VersionedFiles.confirmDelete,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.confirmationConfirmed) },
                onDismiss: { store.send(.confirmationCancelled) }
            )
        }
    }

    // MARK: Summary and filters

    @ViewBuilder
    private var summary: some View {
        if let page = store.page {
            DSInfoCard(L10n.VersionedFiles.summary(
                page.total,
                page.totalVersions,
                TrashSettingsView.bytes(page.totalBytes)
            ))
        }
    }

    @ViewBuilder
    private var filtersCard: some View {
        Card {
            DSTextField(L10n.VersionedFiles.searchPlaceholder, text: $store.filter.query.sending(\.queryChanged))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { store.send(.searchSubmitted) }
        }
        if let zones = store.page?.zones, !zones.isEmpty {
            Card(L10n.VersionedFiles.zone) {
                ChoiceMenuRow(
                    selection: $store.filter.zoneID.sending(\.zoneFilterChanged),
                    valueTitle: zones.first { $0.id == store.filter.zoneID }.map(zoneLabel)
                        ?? L10n.VersionedFiles.anyZone
                ) {
                    Text(L10n.VersionedFiles.anyZone).tag(String?.none)
                    ForEach(zones) { zone in
                        Text(zoneLabel(zone)).tag(String?.some(zone.id))
                    }
                }
            }
        }
        DSButton(L10n.VersionedFiles.refresh, icon: IconKit.retry, style: .secondary, isLoading: store.isReloading) {
            store.send(.refreshTapped)
        }
        .formActionAlignment()
        Card(L10n.VersionedFiles.stateHeader) {
            ChoiceRowList(
                items: [VersionedFileState?.none] + VersionedFileState.allCases.map { Optional($0) },
                title: stateTitle,
                isSelected: { store.filter.state == $0 },
                edges: .both,
                onSelect: { store.send(.stateFilterChanged($0)) }
            )
        }
        Card(L10n.VersionedFiles.sortHeader) {
            ChoiceRowList(
                items: VersionedFileSort.allCases,
                title: sortTitle,
                isSelected: { store.filter.sort == $0 },
                edges: .both,
                onSelect: { store.send(.sortChanged($0)) }
            )
        }
    }

    // MARK: Files

    @ViewBuilder
    private var filesList: some View {
        if store.files.isEmpty, store.phase == .loaded {
            DSInfoCard(L10n.VersionedFiles.none)
        }
        ForEach(store.files) { file in
            fileCard(file)
        }
    }

    private func fileCard(_ file: VersionedFile) -> some View {
        Card {
            Button { store.send(.fileToggled(file.id)) } label: {
                HStack(alignment: .top, spacing: ServerSettingsMetrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: .space4) {
                        Text(file.name).type(.body2(.semibold), style: .primaryOnSurface)
                        if !file.folder.isEmpty {
                            Text(file.folder).type(.body3(.regular), style: .secondary).monospaced()
                        }
                        Text(zoneLabel(file.zone)).type(.body3(.regular), style: .secondary)
                        Text(stateTitle(file.state)).type(.body3(.semibold), style: stateStyle(file.state))
                        Text(L10n.VersionedFiles.rowSummary(file.versions, TrashSettingsView.bytes(file.bytes)))
                            .type(.body3(.regular), style: .tertiary)
                        if let newest = Self.date(file.newest) {
                            Text(L10n.VersionedFiles.newest(newest)).type(.body3(.regular), style: .tertiary)
                        }
                    }
                    Spacer(minLength: ServerSettingsMetrics.rowSpacing)
                    IconKit.chevronDown
                        .foregroundStyle(Color.secondaryDS)
                        .rotationEffect(.degrees(store.expanded.contains(file.id)
                                ? Constants.expandedChevronDegrees
                                : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(store.expanded.contains(file.id) ? .isSelected : [])

            if store.expanded.contains(file.id) {
                detail(file)
            }
        }
    }

    @ViewBuilder
    private func detail(_ file: VersionedFile) -> some View {
        Divider()
        if let message = store.detailErrors[file.id] {
            Text(message).type(.body3(.regular), style: .error)
        } else if let detail = store.details[file.id] {
            let byID = Dictionary(detail.versions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ChoiceRowList(
                items: detail.versions.map(\.id),
                title: { byID[$0].map(versionTitle) ?? $0 },
                subtitle: { byID[$0].flatMap(versionSubtitle) },
                isSelected: { store.selection[file.id]?.contains($0) ?? false },
                indicator: .check,
                isDisabled: store.isWorking,
                onSelect: { store.send(.versionToggled(fileID: file.id, versionID: $0)) }
            )
            let count = store.selection[file.id]?.count ?? 0
            DSButton(
                count == 0 ? L10n.VersionedFiles.deleteSelectedNone : L10n.VersionedFiles.deleteSelected(count),
                style: .secondary
            ) {
                store.send(.deleteSelectedTapped(fileID: file.id))
            }
            .disabled(count == 0 || store.isWorking)
            DSButton(L10n.VersionedFiles.deleteAll, icon: IconKit.delete, style: .failure, isLoading: store.isWorking) {
                store.send(.deleteAllTapped(fileID: file.id))
            }
            .disabled(store.isWorking)
        } else {
            DSSpinner()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Paging

    @ViewBuilder
    private var pager: some View {
        if let page = store.page, page.total > 0 {
            VStack(spacing: ServerSettingsMetrics.rowSpacing) {
                Text(L10n.VersionedFiles.pageRange(page.firstShown, page.lastShown, page.total))
                    .type(.body3(.regular), style: .secondary)
                HStack(spacing: ServerSettingsMetrics.rowSpacing) {
                    DSButton(L10n.VersionedFiles.previous, style: .secondary) {
                        store.send(.previousPageTapped)
                    }
                    .disabled(!page.hasPrevious || store.isReloading)
                    DSButton(L10n.VersionedFiles.next, style: .secondary) {
                        store.send(.nextPageTapped)
                    }
                    .disabled(!page.hasNext || store.isReloading)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Words

    private var confirmationTitle: String {
        switch store.confirmation {
        case let .all(fileID):
            L10n.VersionedFiles.confirmAllTitle(store.files.first { $0.id == fileID }?.name ?? "")
        case let .selected(_, versionIDs):
            L10n.VersionedFiles.confirmSomeTitle(versionIDs.count)
        case .none:
            ""
        }
    }

    private func zoneLabel(_ zone: VersionedZone?) -> String {
        guard let zone else { return L10n.VersionedFiles.zoneUnknown }
        switch zone.kind {
        case .personal: return L10n.VersionedFiles.zoneKindPersonal(zone.name)
        case .userVolume: return L10n.VersionedFiles.zoneKindUserVolume(zone.name)
        case .volume: return zone.name
        }
    }

    private func stateTitle(_ state: VersionedFileState?) -> String {
        switch state {
        case .none: L10n.VersionedFiles.anyState
        case .live: L10n.VersionedFiles.stateLive
        case .trashed: L10n.VersionedFiles.stateTrashed
        case .orphaned: L10n.VersionedFiles.stateOrphaned
        }
    }

    private func stateStyle(_ state: VersionedFileState) -> Typography.TextStyle {
        switch state {
        case .live: .secondary
        case .trashed: .secondary
        case .orphaned: .error
        }
    }

    private func sortTitle(_ sort: VersionedFileSort) -> String {
        switch sort {
        case .bytes: L10n.VersionedFiles.sortBytes
        case .versions: L10n.VersionedFiles.sortVersions
        case .newest: L10n.VersionedFiles.sortNewest
        case .path: L10n.VersionedFiles.sortPath
        }
    }

    private func versionTitle(_ version: FileVersion) -> String {
        "\(version.modifiedAt.formatted(date: .abbreviated, time: .shortened)) · \(TrashSettingsView.bytes(Int(version.size)))"
    }

    private func versionSubtitle(_ version: FileVersion) -> String? {
        var parts: [String] = []
        if let label = version.label, !label.isEmpty {
            parts.append(label)
        }
        if version.isPinned {
            parts.append(L10n.VersionedFiles.versionPinned)
        }
        if version.isAvailable == false {
            parts.append(L10n.VersionedFiles.versionUnavailable)
        }
        if let author = version.author?.label, !author.isEmpty {
            parts.append(L10n.VersionedFiles.versionBy(author))
        }
        return parts.isEmpty ? nil : ServerSettingsMetrics.joined(parts)
    }

    private static func date(_ iso: String?) -> String? {
        iso.flatMap(ServerTimestamp.date(from:))?.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum PreviewVersions {
    static let zone = VersionedZone(id: "z1", name: "Photos")
    static let files = [
        VersionedFile(
            id: "f1",
            name: "report.docx",
            folder: "Work",
            versions: 3,
            bytes: 4_200_000,
            newest: "2026-11-11T07:00:00.000Z",
            zone: zone
        ),
        VersionedFile(id: "f2", name: "lost.txt", state: .orphaned, versions: 1, bytes: 900, zone: zone),
    ]
    static let page = VersionedFilesPage(files: files, total: 2, totalBytes: 4_200_900, totalVersions: 4, zones: [zone])
    static let detail = VersionedFileDetail(versions: [
        FileVersion(
            id: "v1",
            size: 1_400_000,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ),
        FileVersion(
            id: "v2",
            size: 1_300_000,
            modifiedAt: Date(timeIntervalSince1970: 1_699_000_000),
            capturedAt: Date(timeIntervalSince1970: 1_699_000_100)
        ),
    ])
}

@MainActor
private func versionsPreview(
    page: VersionedFilesPage? = PreviewVersions.page,
    phase: DataPhase = .loaded,
    expanded: Bool = false,
    confirming: Bool = false
) -> some View {
    NavigationStack {
        VersionedFilesView(store: Store(initialState: {
            var state = VersionedFilesFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.page = page
            state.phase = phase
            if expanded {
                state.expanded = ["f1"]
                state.details = ["f1": PreviewVersions.detail]
                state.selection = ["f1": ["v1"]]
            }
            if confirming {
                state.confirmation = .selected(fileID: "f1", versionIDs: ["v1"])
            }
            return state
        }()) { VersionedFilesFeature() } withDependencies: {
            $0.filesClient.fetchVersionedFiles = { _, _, _, _ in
                if case .failed = phase {
                    throw FilesClientError.offline
                }
                return page ?? VersionedFilesPage()
            }
            $0.filesClient.fetchVersionedFile = { _, _ in PreviewVersions.detail }
        })
    }
}

#Preview("Files with history") {
    versionsPreview()
}

#Preview("Open history with a selection") {
    versionsPreview(expanded: true)
}

#Preview("Confirm delete") {
    versionsPreview(expanded: true, confirming: true)
}

#Preview("Empty") {
    versionsPreview(page: VersionedFilesPage())
}

#Preview("Failed") {
    versionsPreview(page: nil, phase: .failed("The server could not be reached."))
}
