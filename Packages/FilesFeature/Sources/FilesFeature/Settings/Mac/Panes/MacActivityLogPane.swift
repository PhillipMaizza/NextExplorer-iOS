#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let searchWidth: CGFloat = 240
        static let retentionWidth: CGFloat = 80
        static let timeWidth: CGFloat = 100
        static let actorWidth: CGFloat = 120
        static let addressWidth: CGFloat = 140
        static let outcomeWidth: CGFloat = .size96
        static let dateStyle = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()
    }

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
                onAppear: { store.send(.onAppear) }
            ) {
                settingsGroup
                filtersRow
                eventsTable
                if let error = store.bannerError {
                    MacNote(error, kind: .error)
                }
            }
            .activityLogClearAlert(store)
        }

        private var settingsGroup: some View {
            MacFormGroup {
                MacSwitchRow(L10n.ActivityLog.enabled, isOn: $store.isEnabledDraft.sending(\.enabledChanged))
                MacFormRow(L10n.ActivityLog.retention) {
                    MacTextField(
                        L10n.ActivityLog.retention,
                        text: Binding(get: { store.retentionText }, set: { store.send(.retentionChanged($0)) })
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: Metrics.retentionWidth)
                    .onSubmit { store.send(.saveSettingsTapped) }
                    if store.isSavingSettings {
                        MacSpinner()
                    }
                    Button(L10n.ActivityLog.saveButton) { store.send(.saveSettingsTapped) }
                        .buttonStyle(.macDS(.primary, size: .small))
                        .disabled(!store.isSaveSettingsEnabled)
                }
                if !store.isRetentionValid {
                    MacFormRow(L10n.ActivityLog.retentionInvalid) { EmptyView() }
                        .foregroundStyle(Color.negativeText)
                }
            }
            .disabled(store.isSavingSettings)
        }

        private var actionLabel: String {
            store.filter.action.map(ActivityActionLabel.title(for:)) ?? L10n.ActivityLog.anyAction
        }

        private var outcomeLabel: String {
            switch store.filter.outcome {
            case .none: L10n.ActivityLog.anyOutcome
            case .ok: L10n.ActivityLog.outcomeOk
            case .refused: L10n.ActivityLog.outcomeRefused
            }
        }

        private var filtersRow: some View {
            HStack(spacing: .space8) {
                MacTextField(
                    L10n.ActivityLog.searchPlaceholder,
                    text: $store.filter.query.sending(\.queryChanged),
                    prompt: L10n.ActivityLog.searchPlaceholder
                )
                .autocorrectionDisabled()
                .onSubmit { store.send(.searchSubmitted) }
                .frame(width: Metrics.searchWidth)
                MacPopup(
                    L10n.ActivityLog.filterAction,
                    valueLabel: actionLabel,
                    selection: $store.filter.action.sending(\.actionFilterChanged)
                ) {
                    Text(L10n.ActivityLog.anyAction).tag(String?.none)
                    ForEach(store.actions, id: \.self) { action in
                        Text(ActivityActionLabel.title(for: action)).tag(String?.some(action))
                    }
                }
                MacPopup(
                    L10n.ActivityLog.filterOutcome,
                    valueLabel: outcomeLabel,
                    selection: $store.filter.outcome.sending(\.outcomeFilterChanged)
                ) {
                    Text(L10n.ActivityLog.anyOutcome).tag(ActivityOutcome?.none)
                    Text(L10n.ActivityLog.outcomeOk).tag(ActivityOutcome?.some(.ok))
                    Text(L10n.ActivityLog.outcomeRefused).tag(ActivityOutcome?.some(.refused))
                }
                Spacer(minLength: .zero)
                Button(L10n.ActivityLog.refresh) { store.send(.refreshTapped) }
                    .buttonStyle(.macDS(.secondary, size: .small))
                    .fixedSize()
            }
            .disabled(!store.isLogEnabled)
        }

        private var eventsTable: some View {
            VStack(alignment: .leading, spacing: .zero) {
                if !store.isLogEnabled, store.events.isEmpty {
                    emptyLine(L10n.ActivityLog.off)
                } else if store.events.isEmpty, store.phase == .loaded {
                    emptyLine(L10n.ActivityLog.none)
                } else {
                    ForEach(Array(store.events.enumerated()), id: \.element.id) { index, event in
                        MacActivityEventRow(event: event, isShaded: index.isMultiple(of: 2))
                    }
                    if store.canLoadMore {
                        Button { store.send(.loadMoreTapped) } label: {
                            Text(L10n.ActivityLog.more)
                                .type(.body2(.semibold), style: .secondary)
                                .padding(.horizontal, .space16)
                                .padding(.vertical, .space8)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoadingMore)
                    }
                }
            }
            .macTableBleed()
        }

        private func emptyLine(_ text: String) -> some View {
            Text(text)
                .type(.body2(.regular), style: .secondary)
                .padding(.horizontal, .space12)
                .frame(height: MacTableMetrics.rowHeight)
        }
    }

    struct MacActivityLogClearButton: View {
        let store: StoreOf<ActivityLogFeature>

        var body: some View {
            if !store.isUnavailable, store.phase.errorMessage == nil {
                Button(L10n.ActivityLog.clear, role: .destructive) { store.send(.clearTapped) }
                    .buttonStyle(.macDS(.secondary))
                    .disabled(store.clearPhase.isRunning || !store.isLogEnabled || store.events.isEmpty)
            }
        }
    }

    private struct MacActivityEventRow: View {
        let event: ActivityEvent
        let isShaded: Bool

        private var summary: String {
            ServerSettingsMetrics.joined([ActivityActionLabel.title(for: event.action), event.target].compactMap { $0 })
        }

        private var time: String {
            guard let date = event.date else { return "" }
            return Calendar.current.isDateInToday(date)
                ? date.formatted(date: .omitted, time: .shortened)
                : date.formatted(Metrics.dateStyle)
        }

        var body: some View {
            HStack(spacing: MacTableMetrics.columnSpacing) {
                Text(time)
                    .type(.body2(.regular), style: .secondary)
                    .frame(width: Metrics.timeWidth, alignment: .leading)
                Text(event.actor ?? "")
                    .type(.body2(.regular), style: .secondary)
                    .frame(width: Metrics.actorWidth, alignment: .leading)
                Text(summary)
                    .type(.body2(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(event.ip ?? "")
                    .type(.body3(.regular), style: .secondary)
                    .monospaced()
                    .frame(width: Metrics.addressWidth, alignment: .leading)
                Group {
                    switch event.outcome {
                    case .ok: MacChip(text: L10n.ActivityLog.outcomeOk, tone: .green)
                    case .refused: MacChip(text: L10n.ActivityLog.outcomeRefused, tone: .red)
                    }
                }
                .frame(width: Metrics.outcomeWidth, alignment: .leading)
            }
            .lineLimit(1)
            .macTableRow(isShaded: isShaded)
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("Events") {
        let settings = ActivitySettings(isEnabled: true, retentionDays: 90)
        var state = ActivityLogFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loadedSettings = settings
        state.isEnabledDraft = settings.isEnabled
        state.events = PreviewEvents.all
        state.isLogEnabled = true
        state.phase = .loaded
        return MacActivityLogPane(store: Store(initialState: state) { ActivityLogFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(activity: settings) }
        })
    }

    #Preview("Failed") {
        var state = ActivityLogFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.phase = .failed(ServerSettingsPreview.errorMessage)
        return MacActivityLogPane(store: Store(initialState: state) { ActivityLogFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in throw FilesClientError.offline }
        })
    }
#endif
