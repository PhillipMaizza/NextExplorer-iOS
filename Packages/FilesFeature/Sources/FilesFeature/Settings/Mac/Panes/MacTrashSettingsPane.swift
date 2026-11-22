#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sizeWidth: CGFloat = 96
        static let columnSpacing: CGFloat = .size20
    }

    struct MacTrashSettingsPane: View {
        @Bindable var store: StoreOf<TrashSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.TrashSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loadedTrash == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
                HStack(alignment: .top, spacing: Metrics.columnSpacing) {
                    VStack(alignment: .leading, spacing: .space24) {
                        trashGroup
                        zonesGroup
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    versionsGroup
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.isSaving)
            }
        }

        private var trashGroup: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(L10n.TrashSettings.trashHeader) {
                    toggleRow(
                        L10n.TrashSettings.enabled,
                        help: L10n.TrashSettings.enabledHelp,
                        isOn: $store.trashDraft.isEnabled.sending(\.trashEnabledChanged)
                    )
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
                    MacFormRow {
                        MacInfoLabel(L10n.TrashSettings.maxSize, info: L10n.TrashSettings.maxSizeHelp)
                    } control: {
                        MacTextField(
                            L10n.TrashSettings.maxSize,
                            text: $store.trashDraft.maxSizeText.sending(\.maxSizeChanged),
                            prompt: L10n.TrashSettings.maxSizeNone
                        )
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: Metrics.sizeWidth)
                    }
                }
                if store.isTrashInvalid {
                    MacNote(L10n.TrashSettings.trashInvalid, kind: .error)
                }
            }
        }

        private var versionsGroup: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(
                    L10n.TrashSettings.versionsHeader,
                    info: [L10n.TrashSettings.versionsSubtitle]
                ) {
                    toggleRow(
                        L10n.TrashSettings.versionsEnabled,
                        help: L10n.TrashSettings.versionsEnabledHelp,
                        isOn: $store.versionsDraft.isEnabled.sending(\.versionsEnabledChanged)
                    )
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
                    versionRow(
                        L10n.TrashSettings.dailyDays,
                        \.dailyDaysText,
                        .dailyDays,
                        VersionsSettings.dailyDaysRange
                    )
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
                }
                if store.isVersionsInvalid {
                    MacNote(L10n.TrashSettings.versionsInvalid, kind: .error)
                }
                MacFormFootnote(L10n.TrashSettings.tiersHelp, L10n.TrashSettings.sharedSpace)
            }
        }

        private var zonesGroup: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(L10n.TrashSettings.zonesHeader, info: [L10n.TrashSettings.zonesSubtitle]) {
                    if store.zones.isEmpty, store.zonesPhase == .loaded {
                        MacFormRow {
                            Text(L10n.TrashSettings.zonesEmpty).foregroundStyle(Color.macChromeSecondary)
                        } control: {
                            EmptyView()
                        }
                    } else if store.zones.isEmpty, store.zonesPhase == .loading {
                        MacFormRow {
                            MacSpinner()
                        } control: {
                            EmptyView()
                        }
                    }
                    ForEach(store.zones) { zone in
                        MacTrashZoneRow(
                            zone: zone,
                            problems: store.verification?.first { $0.zoneID == zone.id }?.violationCount ?? 0
                        )
                    }
                }
                if let zonesError = store.zonesError {
                    MacNote(zonesError, kind: .error)
                }
                if !store.zones.isEmpty {
                    HStack(spacing: .space8) {
                        Button(L10n.TrashSettings.verify) { store.send(.verifyTapped) }
                            .buttonStyle(.macDS(.secondary, size: .small))
                            .disabled(store.isVerifying)
                        if store.isVerifying {
                            MacSpinner()
                        } else if store.verification != nil {
                            verificationSummary
                        }
                    }
                    .padding(.top, .space4)
                }
            }
        }

        @ViewBuilder
        private var verificationSummary: some View {
            if store.totalViolations == 0 {
                Text(L10n.TrashSettings.verifyOk).type(.body3(.regular), style: .secondary)
            } else {
                Text(L10n.TrashSettings.verifyIssues(store.totalViolations)).type(.body3(.regular), style: .error)
            }
        }

        private func toggleRow(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
            MacSwitchRow(title: title, isOn: isOn) { MacInfoLabel(title, info: help) }
        }

        private func stepperRow(
            _ title: String,
            help: String? = nil,
            text: String,
            range: ClosedRange<Int>,
            onChange: @escaping (String) -> Void
        ) -> some View {
            MacStepperRow(
                title: title,
                value: Int(text) ?? range.lowerBound,
                range: range,
                onChange: { onChange(String($0)) },
                label: {
                    if let help {
                        MacInfoLabel(title, info: help)
                    } else {
                        Text(title)
                    }
                }
            )
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
    }

    struct MacTrashSettingsTools: View {
        let store: StoreOf<TrashSettingsFeature>

        var body: some View {
            HStack(spacing: .space8) {
                if store.isMaintaining {
                    MacSpinner()
                }
                Button(L10n.TrashSettings.runMaintenance) { store.send(.maintenanceTapped) }
                    .buttonStyle(.macDS(.secondary))
                    .disabled(store.isMaintaining || store.zones.isEmpty)
                MacPaneSaveButton(
                    title: L10n.TrashSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled
                ) { store.send(.saveTapped) }
            }
        }
    }

    @MainActor
    private func trashPanePreview(_ state: TrashSettingsFeature.State) -> some View {
        let store = Store(initialState: state) {
            EmptyReducer<TrashSettingsFeature.State, TrashSettingsFeature.Action>()
        }
        return MacSettingsPaneCard(title: L10n.TrashSettings.navigationTitle, subtitle: nil) {
            MacTrashSettingsPane(store: store)
        } tools: {
            MacTrashSettingsTools(store: store)
        }
        .previewCanvas(.settingsWindow)
        .background(Color.macChrome)
    }

    #Preview("Volumes") {
        trashPanePreview(.preview(zones: [PreviewZones.available, PreviewZones.missing]))
    }

    #Preview("Verified with problems") {
        trashPanePreview(.preview(
            zones: [PreviewZones.available, PreviewZones.missing],
            verification: [TrashVerification(
                zoneID: PreviewZones.available.id,
                violations: [.init(invariant: "count", detail: "2 items without a record")]
            )]
        ))
    }

    #Preview("No volumes, invalid") {
        trashPanePreview(.preview(retentionText: "0"))
    }
#endif
