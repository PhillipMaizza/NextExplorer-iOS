#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sizeWidth: CGFloat = 90
    }

    /// The Trash and Versions pane: both forms, then each volume's trash space.
    struct MacTrashSettingsPane: View {
        @Bindable var store: StoreOf<TrashSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.TrashSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loadedTrash == nil,
                save: MacAdminSave(
                    title: L10n.TrashSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled,
                    action: { store.send(.saveTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                trashSection
                versionsSection
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
                zonesSections
            }
        }

        private var trashSection: some View {
            Section(L10n.TrashSettings.trashHeader) {
                Toggle(isOn: $store.trashDraft.isEnabled.sending(\.trashEnabledChanged)) {
                    MacRowTitle(title: L10n.TrashSettings.enabled, subtitle: L10n.TrashSettings.enabledHelp)
                }
                stepperRow(
                    L10n.TrashSettings.retention,
                    help: L10n.TrashSettings.retentionHelp,
                    text: store.trashDraft.retentionText,
                    range: TrashSettings.retentionRange
                ) { store.send(.retentionChanged($0)) }
                stepperRow(
                    L10n.TrashSettings.maxPercent,
                    help: L10n.TrashSettings.maxPercentHelp,
                    text: store.trashDraft.maxPercentText,
                    range: TrashSettings.maxPercentRange
                ) { store.send(.maxPercentChanged($0)) }
                sizeCapRow
                if store.isTrashInvalid {
                    Text(L10n.TrashSettings.trashInvalid).foregroundStyle(Color.negativeText)
                }
            }
        }

        private var versionsSection: some View {
            Section {
                Toggle(isOn: $store.versionsDraft.isEnabled.sending(\.versionsEnabledChanged)) {
                    MacRowTitle(
                        title: L10n.TrashSettings.versionsEnabled,
                        subtitle: L10n.TrashSettings.versionsEnabledHelp
                    )
                }
                versionRow(
                    L10n.TrashSettings.keepAllHours,
                    \.keepAllHoursText,
                    .keepAllHours,
                    VersionsSettings.keepAllHoursRange
                )
                versionRow(
                    L10n.TrashSettings.hourlyDays,
                    \.hourlyDaysText,
                    .hourlyDays,
                    VersionsSettings.hourlyDaysRange
                )
                versionRow(L10n.TrashSettings.dailyDays, \.dailyDaysText, .dailyDays, VersionsSettings.dailyDaysRange)
                versionRow(
                    L10n.TrashSettings.maxPerFile,
                    \.maxPerFileText,
                    .maxPerFile,
                    VersionsSettings.maxPerFileRange
                )
                versionRow(
                    L10n.TrashSettings.checkpointMinutes,
                    \.checkpointMinutesText,
                    .checkpointMinutes,
                    VersionsSettings.sessionCheckpointMinutesRange
                )
                if store.isVersionsInvalid {
                    Text(L10n.TrashSettings.versionsInvalid).foregroundStyle(Color.negativeText)
                }
            } header: {
                Text(L10n.TrashSettings.versionsHeader)
            } footer: {
                MacSectionFooter(
                    L10n.TrashSettings.versionsSubtitle,
                    L10n.TrashSettings.tiersHelp,
                    L10n.TrashSettings.sharedSpace
                )
            }
        }

        /// A whole number with its stepper, like the Thumbnails pane. The field clamps to the range,
        /// so what is typed is always something the server accepts.
        private func stepperRow(
            _ title: String,
            help: String? = nil,
            text: String,
            range: ClosedRange<Int>,
            onChange: @escaping (String) -> Void
        ) -> some View {
            LabeledContent {
                MacNumberStepper(label: title, value: Int(text) ?? range.lowerBound, range: range, step: 1) {
                    onChange(String($0))
                }
            } label: {
                if let help {
                    MacRowTitle(title: title, subtitle: help)
                } else {
                    Text(title)
                }
            }
        }

        /// The optional size cap: decimal, and empty for none, so it stays a text field.
        private var sizeCapRow: some View {
            LabeledContent {
                TextField(
                    L10n.TrashSettings.maxSize,
                    text: $store.trashDraft.maxSizeText.sending(\.maxSizeChanged),
                    prompt: Text(L10n.TrashSettings.maxSizeNone)
                )
                .labelsHidden()
                .macEditableField()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: Metrics.sizeWidth)
            } label: {
                MacRowTitle(title: L10n.TrashSettings.maxSize, subtitle: L10n.TrashSettings.maxSizeHelp)
            }
        }

        private func versionRow(
            _ title: String,
            _ keyPath: KeyPath<TrashSettingsFeature.VersionsDraft, String>,
            _ field: TrashSettingsFeature.VersionField,
            _ range: ClosedRange<Int>
        ) -> some View {
            stepperRow(title, text: store.versionsDraft[keyPath: keyPath], range: range) {
                store.send(.versionFieldChanged(field, $0))
            }
        }

        // MARK: Volumes

        private var zonesSections: some View {
            Section {
                if let zonesError = store.zonesError {
                    Text(zonesError).foregroundStyle(Color.negativeText)
                }
                if store.zones.isEmpty, store.zonesPhase == .loaded {
                    Text(L10n.TrashSettings.zonesEmpty).foregroundStyle(.secondary)
                }
                ForEach(store.zones) { zone in
                    zoneRow(zone)
                }
                if !store.zones.isEmpty {
                    verificationSummary
                    HStack {
                        Spacer()
                        Button(L10n.TrashSettings.verify) { store.send(.verifyTapped) }
                            .disabled(store.isVerifying)
                        Button(L10n.TrashSettings.runMaintenance) { store.send(.maintenanceTapped) }
                            .disabled(store.isMaintaining)
                    }
                }
            } header: {
                Text(L10n.TrashSettings.zonesHeader)
            } footer: {
                MacSectionFooter(L10n.TrashSettings.zonesSubtitle)
            }
        }

        @ViewBuilder
        private var verificationSummary: some View {
            if store.verification != nil {
                if store.totalViolations == 0 {
                    Text(L10n.TrashSettings.verifyOk).foregroundStyle(.secondary)
                } else {
                    Text(L10n.TrashSettings.verifyIssues(store.totalViolations)).foregroundStyle(Color.negativeText)
                }
            }
        }

        private func zoneRow(_ zone: TrashZone) -> some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(zoneTitle(zone)).fontWeight(.semibold)
                Text(zoneState(zone)).font(.callout)
                    .foregroundStyle(zone.isAvailable ? Color.secondary : Color.negativeText)
                if zone.isAvailable {
                    ProgressView(value: zone.usedFraction)
                    Text(L10n.TrashSettings.usage(
                        TrashSettingsView.bytes(zone.heldBytes),
                        zone.budgetBytes.map(TrashSettingsView.bytes) ?? L10n.TrashSettings.noBudget
                    ))
                    .font(.callout).foregroundStyle(.secondary)
                    Text(ServerSettingsMetrics.joined([
                        L10n.TrashSettings.zoneItems(zone.itemCount, TrashSettingsView.bytes(zone.usedBytes)),
                        L10n.TrashSettings.zoneVersions(zone.versionCount, TrashSettingsView.bytes(zone.versionBytes)),
                    ]))
                    .font(.callout).foregroundStyle(.secondary)
                }
                if let problems = store.verification?.first(where: { $0.zoneID == zone.id })?.violationCount,
                   problems > 0
                {
                    Text(L10n.TrashSettings.zoneProblems(problems)).font(.callout).foregroundStyle(Color.negativeText)
                }
                ForEach(zone.events) { event in
                    Text(TrashEventLabel.text(for: event)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }

        private func zoneTitle(_ zone: TrashZone) -> String {
            switch zone.kind {
            case .personal: L10n.TrashSettings.zoneKindPersonal(zone.name)
            case .userVolume: L10n.TrashSettings.zoneKindUserVolume(zone.name)
            case .volume: zone.name
            }
        }

        private func zoneState(_ zone: TrashZone) -> String {
            guard !zone.isAvailable else { return L10n.TrashSettings.available }
            switch zone.reason {
            case "replaced": return L10n.TrashSettings.unavailableReplaced
            case "unreadable": return L10n.TrashSettings.unavailableUnreadable
            default: return L10n.TrashSettings.unavailableMissing
            }
        }
    }
#endif
