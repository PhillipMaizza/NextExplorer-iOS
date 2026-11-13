#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Activity Log pane: the switch and retention, the filters, the lines of the log, and
    /// emptying it.
    struct MacActivityLogPane: View {
        @Bindable var store: StoreOf<ActivityLogFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.ActivityLog.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.events.isEmpty,
                save: MacAdminSave(
                    title: L10n.ActivityLog.saveButton,
                    isSaving: store.isSavingSettings,
                    isEnabled: store.isSaveSettingsEnabled,
                    action: { store.send(.saveSettingsTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                settingsSection
                filtersSection
                eventsSection
                Section {
                    Button(L10n.ActivityLog.clear, role: .destructive) { store.send(.clearTapped) }
                        .disabled(store.isClearing)
                }
                if let error = store.settingsError ?? store.listError {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            .confirmationDialog(
                L10n.ActivityLog.clearTitle,
                isPresented: Binding(get: { store.isConfirmingClear }, set: { _ in })
            ) {
                Button(L10n.ActivityLog.clearConfirm, role: .destructive) { store.send(.clearConfirmed) }
                Button(L10n.Common.cancel, role: .cancel) { store.send(.clearCancelled) }
            } message: {
                Text(L10n.ActivityLog.clearMessage)
            }
        }

        private var settingsSection: some View {
            Section {
                Toggle(isOn: $store.isEnabledDraft.sending(\.enabledChanged)) {
                    MacRowTitle(title: L10n.ActivityLog.enabled, subtitle: L10n.ActivityLog.enabledHelp)
                }
                LabeledContent(L10n.ActivityLog.retention) {
                    MacNumberStepper(
                        label: L10n.ActivityLog.retention,
                        value: Int(store.retentionText) ?? ActivitySettings.retentionRange.lowerBound,
                        range: ActivitySettings.retentionRange,
                        step: 1
                    ) { store.send(.retentionChanged(String($0))) }
                }
                if !store.isRetentionValid {
                    Text(L10n.ActivityLog.retentionInvalid).foregroundStyle(Color.negativeText)
                }
            } footer: {
                MacSectionFooter(L10n.ActivityLog.subtitle)
            }
        }

        private var filtersSection: some View {
            Section {
                Picker(L10n.ActivityLog.filterAction, selection: $store.filter.action.sending(\.actionFilterChanged)) {
                    Text(L10n.ActivityLog.anyAction).tag(String?.none)
                    ForEach(store.actions, id: \.self) { action in
                        Text(ActivityActionLabel.title(for: action)).tag(String?.some(action))
                    }
                }
                Picker(
                    L10n.ActivityLog.filterOutcome,
                    selection: $store.filter.outcome.sending(\.outcomeFilterChanged)
                ) {
                    Text(L10n.ActivityLog.anyOutcome).tag(ActivityOutcome?.none)
                    Text(L10n.ActivityLog.outcomeOk).tag(ActivityOutcome?.some(.ok))
                    Text(L10n.ActivityLog.outcomeRefused).tag(ActivityOutcome?.some(.refused))
                }
                HStack(spacing: .space8) {
                    TextField(
                        L10n.ActivityLog.searchPlaceholder,
                        text: $store.filter.query.sending(\.queryChanged),
                        prompt: Text(L10n.ActivityLog.searchPlaceholder)
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { store.send(.searchSubmitted) }
                    Button(L10n.ActivityLog.refresh) { store.send(.refreshTapped) }
                }
            }
        }

        @ViewBuilder
        private var eventsSection: some View {
            if !store.isLogEnabled, store.events.isEmpty {
                Section { Text(L10n.ActivityLog.off).foregroundStyle(.secondary) }
            } else if store.events.isEmpty, store.phase == .loaded {
                Section { Text(L10n.ActivityLog.none).foregroundStyle(.secondary) }
            } else if !store.events.isEmpty {
                Section {
                    ForEach(store.events) { event in
                        eventRow(event)
                    }
                    if store.canLoadMore {
                        HStack {
                            Spacer()
                            Button(L10n.ActivityLog.more) { store.send(.loadMoreTapped) }
                                .disabled(store.isLoadingMore)
                        }
                    }
                }
            }
        }

        private func eventRow(_ event: ActivityEvent) -> some View {
            VStack(alignment: .leading, spacing: .space2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ActivityActionLabel.title(for: event.action)).fontWeight(.semibold)
                    if event.outcome == .refused {
                        RefusedTag()
                    }
                    Spacer()
                    if let date = event.date {
                        Text(date.formatted(date: .abbreviated, time: .standard)).foregroundStyle(.secondary)
                    }
                }
                let details = [event.actor, event.target, event.ip.map { L10n.ActivityLog.fromAddress($0) }]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(ServerSettingsMetrics.joined(details)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
#endif
