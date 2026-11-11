import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The label for a kind of event, in the reader's language. The server names them `share.download`
/// and the like, so one this app has never heard of falls back to its own name.
enum ActivityActionLabel {
    static func title(for action: String) -> String {
        switch action {
        case "sign-in": L10n.ActivityLog.actionSignIn
        case "sign-out": L10n.ActivityLog.actionSignOut
        case "account.password": L10n.ActivityLog.actionAccountPassword
        case "account.two-factor": L10n.ActivityLog.actionAccountTwoFactor
        case "account.passkey": L10n.ActivityLog.actionAccountPasskey
        case "account.token": L10n.ActivityLog.actionAccountToken
        case "admin.user": L10n.ActivityLog.actionAdminUser
        case "admin.settings": L10n.ActivityLog.actionAdminSettings
        case "admin.activity-clear": L10n.ActivityLog.actionAdminActivityClear
        case "share.create": L10n.ActivityLog.actionShareCreate
        case "share.delete": L10n.ActivityLog.actionShareDelete
        case "share.download": L10n.ActivityLog.actionShareDownload
        case "share.upload": L10n.ActivityLog.actionShareUpload
        case "file.download": L10n.ActivityLog.actionFileDownload
        case "file.upload": L10n.ActivityLog.actionFileUpload
        case "file.delete": L10n.ActivityLog.actionFileDelete
        case "file.restore": L10n.ActivityLog.actionFileRestore
        case "file.purge": L10n.ActivityLog.actionFilePurge
        case "versions.purge": L10n.ActivityLog.actionVersionsPurge
        default: action
        }
    }
}

/// Admin editor and reader for the activity log, pushed from the Settings admin section.
struct ActivityLogView: View {
    @Bindable var store: StoreOf<ActivityLogFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.ActivityLog.navigationTitle,
            subtitle: L10n.ActivityLog.subtitle,
            unavailableMessage: L10n.ActivityLog.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.settingsError ?? store.listError,
            isLoadingFirstTime: store.phase == .loading && store.events.isEmpty,
            isBusy: store.isSavingSettings,
            onAppear: { store.send(.onAppear) }
        ) {
            settingsCard
            filtersCard
            eventsCard
            clearButton
        }
        .dsAlert(isPresented: Binding(get: { store.isConfirmingClear }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: L10n.ActivityLog.clearTitle,
                message: L10n.ActivityLog.clearMessage,
                confirmTitle: L10n.ActivityLog.clearConfirm,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.clearConfirmed) },
                onDismiss: { store.send(.clearCancelled) }
            )
        }
    }

    private var settingsCard: some View {
        Card {
            DSToggleRow(
                title: L10n.ActivityLog.enabled,
                subtitle: L10n.ActivityLog.enabledHelp,
                icon: IconKit.time,
                isOn: $store.isEnabledDraft.sending(\.enabledChanged)
            )
            VStack(alignment: .leading, spacing: ServerSettingsMetrics.rowSpacing) {
                DSFieldLabel(L10n.ActivityLog.retention)
                DSTextField(L10n.ActivityLog.retention, text: $store.retentionText.sending(\.retentionChanged))
                    .keyboardType(.numberPad)
                if !store.isRetentionValid {
                    Text(L10n.ActivityLog.retentionInvalid)
                        .type(.body3(.regular), style: .error)
                }
            }
            .padding(.top, ServerSettingsMetrics.fieldGroupInset)
            DSButton(L10n.ActivityLog.saveButton, style: .primary, isLoading: store.isSavingSettings) {
                store.send(.saveSettingsTapped)
            }
            .disabled(!store.isSaveSettingsEnabled)
            .formActionAlignment()
        }
    }

    @ViewBuilder
    private var filtersCard: some View {
        Card(L10n.ActivityLog.filterAction) {
            ChoiceMenuRow(
                selection: $store.filter.action.sending(\.actionFilterChanged),
                valueTitle: store.filter.action.map(ActivityActionLabel.title(for:)) ?? L10n.ActivityLog.anyAction
            ) {
                Text(L10n.ActivityLog.anyAction).tag(String?.none)
                ForEach(store.actions, id: \.self) { action in
                    Text(ActivityActionLabel.title(for: action)).tag(String?.some(action))
                }
            }
        }
        Card(L10n.ActivityLog.filterOutcome) {
            ChoiceRowList(
                items: [ActivityOutcome?.none, .some(.ok), .some(.refused)],
                title: outcomeTitle,
                isSelected: { store.filter.outcome == $0 },
                edges: .both,
                onSelect: { store.send(.outcomeFilterChanged($0)) }
            )
        }
        Card {
            DSTextField(
                L10n.ActivityLog.searchPlaceholder,
                text: $store.filter.query.sending(\.queryChanged)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { store.send(.searchSubmitted) }
            DSButton(L10n.ActivityLog.refresh, icon: IconKit.retry, style: .secondary) {
                store.send(.refreshTapped)
            }
            .formActionAlignment()
        }
    }

    @ViewBuilder
    private var eventsCard: some View {
        if !store.isLogEnabled, store.phase == .loaded {
            DSInfoCard(L10n.ActivityLog.off)
        }
        if store.events.isEmpty {
            if store.isLogEnabled, store.phase == .loaded {
                DSInfoCard(L10n.ActivityLog.none)
            }
        } else {
            Card {
                FlushRows(edges: store.canLoadMore ? .top : .both) {
                    ForEach(Array(store.events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Divider()
                        }
                        eventRow(event)
                    }
                }
                if store.canLoadMore {
                    DSButton(L10n.ActivityLog.more, style: .secondary, isLoading: store.isLoadingMore) {
                        store.send(.loadMoreTapped)
                    }
                    .formActionAlignment()
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: .space4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ActivityActionLabel.title(for: event.action))
                    .type(.body2(.semibold), style: .primaryOnSurface)
                if event.outcome == .refused {
                    RefusedTag()
                }
                Spacer(minLength: ServerSettingsMetrics.rowSpacing)
                if let date = event.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .type(.body3(.regular), style: .tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let actor = event.actor {
                Text(actor).type(.body3(.regular), style: .secondary)
            }
            if let target = event.target {
                Text(target).type(.body3(.regular), style: .secondary).monospaced()
            }
            if let ip = event.ip {
                Text(L10n.ActivityLog.fromAddress(ip)).type(.body3(.regular), style: .tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ServerSettingsMetrics.choiceRowVerticalPadding)
    }

    private func outcomeTitle(_ outcome: ActivityOutcome?) -> String {
        switch outcome {
        case .none: L10n.ActivityLog.anyOutcome
        case .ok: L10n.ActivityLog.outcomeOk
        case .refused: L10n.ActivityLog.outcomeRefused
        }
    }

    private var clearButton: some View {
        DSButton(L10n.ActivityLog.clear, icon: IconKit.delete, style: .failure, isLoading: store.isClearing) {
            store.send(.clearTapped)
        }
        .formActionAlignment()
    }
}

private enum PreviewEvents {
    static let all = [
        ActivityEvent(id: "1", at: "2026-11-11T07:00:00.000Z", action: "sign-in", actor: "phillip", ip: "192.168.1.20"),
        ActivityEvent(id: "2", at: "2026-11-11T06:58:00.000Z", action: "sign-in", outcome: .refused, actor: "intruder@example.com", ip: "203.0.113.9"),
        ActivityEvent(id: "3", at: "2026-11-11T06:30:00.000Z", action: "file.delete", actor: "phillip", target: "Documents/old.txt"),
    ]
}

@MainActor
private func activityPreview(
    events: [ActivityEvent] = PreviewEvents.all,
    isLogEnabled: Bool = true,
    nextBefore: String? = "2026-11-11T06:30:00.000Z",
    phase: DataPhase = .loaded,
    unavailable: Bool = false
) -> some View {
    let settings = ActivitySettings(isEnabled: isLogEnabled, retentionDays: 90)
    return NavigationStack {
        ActivityLogView(store: Store(initialState: {
            var state = ActivityLogFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loadedSettings = settings
            state.isEnabledDraft = settings.isEnabled
            state.events = events
            state.actions = ["sign-in", "file.delete"]
            state.isLogEnabled = isLogEnabled
            state.nextBefore = nextBefore
            state.phase = phase
            state.isUnavailable = unavailable
            return state
        }()) { ActivityLogFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in unavailable ? SystemSettings() : SystemSettings(activity: settings) }
            $0.filesClient.fetchActivity = { _, _, _ in
                if case .failed = phase {
                    throw FilesClientError.offline
                }
                return ActivityPage(events: events, nextBefore: nextBefore, isEnabled: isLogEnabled, actions: ["sign-in", "file.delete"])
            }
        })
    }
}

#Preview("Events") {
    activityPreview()
}

#Preview("Recording off, old lines kept") {
    activityPreview(isLogEnabled: false, nextBefore: nil)
}

#Preview("Nothing recorded yet") {
    activityPreview(events: [], nextBefore: nil)
}

#Preview("Failed") {
    activityPreview(events: [], nextBefore: nil, phase: .failed("The server could not be reached."))
}

#Preview("Not an admin") {
    activityPreview(events: [], nextBefore: nil, unavailable: true)
}
