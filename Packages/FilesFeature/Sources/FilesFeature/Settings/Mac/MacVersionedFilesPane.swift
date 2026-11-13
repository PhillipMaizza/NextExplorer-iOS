#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sectionSpacing: CGFloat = .space12
        static let versionRowSpacing: CGFloat = .space12
        static let expandedChevronDegrees: Double = 180
    }

    /// The File Versions pane: every file that has a history, filtered and paged, each opening to
    /// its versions for deleting.
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
                summarySection
                filtersSection
                filesSection
                pagerSection
                if let error = store.listError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(get: { store.confirmation != nil }, set: { _ in })
            ) {
                Button(L10n.VersionedFiles.confirmDelete, role: .destructive) { store.send(.confirmationConfirmed) }
                Button(L10n.Common.cancel, role: .cancel) { store.send(.confirmationCancelled) }
            } message: {
                Text(L10n.VersionedFiles.confirmMessage)
            }
        }

        @ViewBuilder
        private var summarySection: some View {
            if let page = store.page {
                Section {
                    Text(L10n.VersionedFiles.summary(
                        page.total,
                        page.totalVersions,
                        TrashSettingsView.bytes(page.totalBytes)
                    ))
                } footer: {
                    MacSectionFooter(L10n.VersionedFiles.subtitle)
                }
            }
        }

        private var filtersSection: some View {
            Section {
                TextField(
                    L10n.VersionedFiles.searchPlaceholder,
                    text: $store.filter.query.sending(\.queryChanged),
                    prompt: Text(L10n.VersionedFiles.searchPlaceholder)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { store.send(.searchSubmitted) }
                if let zones = store.page?.zones, !zones.isEmpty {
                    Picker(L10n.VersionedFiles.zone, selection: $store.filter.zoneID.sending(\.zoneFilterChanged)) {
                        Text(L10n.VersionedFiles.anyZone).tag(String?.none)
                        ForEach(zones) { zone in
                            Text(zoneLabel(zone)).tag(String?.some(zone.id))
                        }
                    }
                }
                Picker(L10n.VersionedFiles.stateHeader, selection: $store.filter.state.sending(\.stateFilterChanged)) {
                    Text(L10n.VersionedFiles.anyState).tag(VersionedFileState?.none)
                    ForEach(VersionedFileState.allCases, id: \.self) { state in
                        Text(stateTitle(state)).tag(VersionedFileState?.some(state))
                    }
                }
                Picker(L10n.VersionedFiles.sortHeader, selection: $store.filter.sort.sending(\.sortChanged)) {
                    ForEach(VersionedFileSort.allCases, id: \.self) { sort in
                        Text(sortTitle(sort)).tag(sort)
                    }
                }
            }
        }

        @ViewBuilder
        private var filesSection: some View {
            if store.files.isEmpty, store.phase == .loaded {
                Section { Text(L10n.VersionedFiles.none).foregroundStyle(.secondary) }
            }
            ForEach(store.files) { file in
                Section {
                    fileRow(file)
                }
            }
        }

        private func fileRow(_ file: VersionedFile) -> some View {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                fileHeader(file)
                if store.expanded.contains(file.id) {
                    Divider()
                    detail(file)
                }
            }
        }

        /// The file's name and where it lives, as one click target that opens its versions.
        private func fileHeader(_ file: VersionedFile) -> some View {
            Button { store.send(.fileToggled(file.id)) } label: {
                HStack(alignment: .top, spacing: Metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(file.name).fontWeight(.semibold)
                        if !file.folder.isEmpty {
                            Text(file.folder).font(.callout).foregroundStyle(.secondary).monospaced()
                        }
                        Text(ServerSettingsMetrics.joined([zoneLabel(file.zone), stateTitle(file.state)]))
                            .font(.callout)
                            .foregroundStyle(file.state == .orphaned ? Color.negativeText : Color.secondary)
                        Text(L10n.VersionedFiles.rowSummary(file.versions, TrashSettingsView.bytes(file.bytes)))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Metrics.sectionSpacing)
                    IconKit.chevronDown
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.expanded.contains(file.id) ? Metrics.expandedChevronDegrees : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(store.expanded.contains(file.id) ? .isSelected : [])
        }

        @ViewBuilder
        private func detail(_ file: VersionedFile) -> some View {
            if let message = store.detailErrors[file.id] {
                Text(message).foregroundStyle(Color.negativeText)
            } else if let detail = store.details[file.id] {
                VStack(alignment: .leading, spacing: Metrics.versionRowSpacing) {
                    ForEach(detail.versions) { version in
                        versionRow(version, fileID: file.id)
                    }
                }
                let count = store.selection[file.id]?.count ?? 0
                HStack(spacing: Metrics.sectionSpacing) {
                    Spacer()
                    Button(count == 0
                        ? L10n.VersionedFiles.deleteSelectedNone
                        : L10n.VersionedFiles
                            .deleteSelected(count))
                    {
                        store.send(.deleteSelectedTapped(fileID: file.id))
                    }
                    .disabled(count == 0 || store.isWorking)
                    Button(L10n.VersionedFiles.deleteAll, role: .destructive) {
                        store.send(.deleteAllTapped(fileID: file.id))
                    }
                    .disabled(store.isWorking)
                }
            } else {
                MacSpinner()
            }
        }

        /// One version on a line of its own: a checkbox, when it was kept and any note, and its size.
        private func versionRow(_ version: FileVersion, fileID: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sectionSpacing) {
                Toggle(isOn: Binding(
                    get: { store.selection[fileID]?.contains(version.id) ?? false },
                    set: { _ in store.send(.versionToggled(fileID: fileID, versionID: version.id)) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(version.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    if let subtitle = versionSubtitle(version) {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Metrics.sectionSpacing)
                Text(TrashSettingsView.bytes(Int(version.size)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture { store.send(.versionToggled(fileID: fileID, versionID: version.id)) }
        }

        @ViewBuilder
        private var pagerSection: some View {
            if let page = store.page, page.total > 0 {
                Section {
                    HStack {
                        Text(L10n.VersionedFiles.pageRange(page.firstShown, page.lastShown, page.total))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.VersionedFiles.previous) { store.send(.previousPageTapped) }
                            .disabled(!page.hasPrevious || store.isReloading)
                        Button(L10n.VersionedFiles.next) { store.send(.nextPageTapped) }
                            .disabled(!page.hasNext || store.isReloading)
                    }
                }
            }
        }

        // MARK: Words

        private var confirmationTitle: String {
            switch store.confirmation {
            case let .all(fileID): L10n.VersionedFiles
                .confirmAllTitle(store.files.first { $0.id == fileID }?.name ?? "")
            case let .selected(_, versionIDs): L10n.VersionedFiles.confirmSomeTitle(versionIDs.count)
            case .none: ""
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

        private func stateTitle(_ state: VersionedFileState) -> String {
            switch state {
            case .live: L10n.VersionedFiles.stateLive
            case .trashed: L10n.VersionedFiles.stateTrashed
            case .orphaned: L10n.VersionedFiles.stateOrphaned
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
    }
#endif
