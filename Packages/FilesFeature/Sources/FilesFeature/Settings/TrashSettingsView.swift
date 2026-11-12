import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Admin editor for the trash and file versions, plus each volume's trash space, pushed from the
/// Settings admin section. Mirrors the web client's `SettingsTrash.vue`.
struct TrashSettingsView: View {
    @Bindable var store: StoreOf<TrashSettingsFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.TrashSettings.navigationTitle,
            subtitle: L10n.TrashSettings.subtitle,
            unavailableMessage: L10n.TrashSettings.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.errorMessage,
            isLoadingFirstTime: store.phase == .loading && store.loadedTrash == nil && !store.isUnavailable,
            isBusy: store.isSaving,
            onAppear: { store.send(.onAppear) }
        ) {
            trashCard
            versionsCard
            saveRow
            zonesSection
        }
    }

    // MARK: Trash

    private var trashCard: some View {
        Card(L10n.TrashSettings.trashHeader) {
            DSToggleRow(
                title: L10n.TrashSettings.enabled,
                subtitle: L10n.TrashSettings.enabledHelp,
                icon: IconKit.delete,
                isOn: $store.trashDraft.isEnabled.sending(\.trashEnabledChanged)
            )
            VStack(alignment: .leading, spacing: ServerSettingsMetrics.fieldGroupSpacing) {
                SettingsNumberField(
                    title: L10n.TrashSettings.retention,
                    help: L10n.TrashSettings.retentionHelp,
                    text: $store.trashDraft.retentionText.sending(\.retentionChanged)
                )
                SettingsNumberField(
                    title: L10n.TrashSettings.maxPercent,
                    help: L10n.TrashSettings.maxPercentHelp,
                    text: $store.trashDraft.maxPercentText.sending(\.maxPercentChanged)
                )
                SettingsNumberField(
                    title: L10n.TrashSettings.maxSize,
                    help: L10n.TrashSettings.maxSizeHelp,
                    placeholder: L10n.TrashSettings.maxSizeNone,
                    text: $store.trashDraft.maxSizeText.sending(\.maxSizeChanged),
                    keyboard: .decimalPad
                )
            }
            .padding(.top, ServerSettingsMetrics.fieldGroupInset)
            if store.isTrashInvalid {
                Text(L10n.TrashSettings.trashInvalid).type(.body3(.regular), style: .error)
            }
            Text(L10n.TrashSettings.environmentNote).type(.body3(.regular), style: .tertiary)
        }
    }

    // MARK: Versions

    private var versionsCard: some View {
        Card(L10n.TrashSettings.versionsHeader) {
            Text(L10n.TrashSettings.versionsSubtitle).type(.body3(.regular), style: .secondary)
            DSToggleRow(
                title: L10n.TrashSettings.versionsEnabled,
                subtitle: L10n.TrashSettings.versionsEnabledHelp,
                icon: IconKit.time,
                isOn: $store.versionsDraft.isEnabled.sending(\.versionsEnabledChanged)
            )
            VStack(alignment: .leading, spacing: ServerSettingsMetrics.fieldGroupSpacing) {
                versionField(L10n.TrashSettings.keepAllHours, \.keepAllHoursText, .keepAllHours)
                versionField(L10n.TrashSettings.hourlyDays, \.hourlyDaysText, .hourlyDays)
                versionField(L10n.TrashSettings.dailyDays, \.dailyDaysText, .dailyDays)
                versionField(L10n.TrashSettings.maxPerFile, \.maxPerFileText, .maxPerFile)
                versionField(L10n.TrashSettings.checkpointMinutes, \.checkpointMinutesText, .checkpointMinutes)
            }
            .padding(.top, ServerSettingsMetrics.fieldGroupInset)
            Text(L10n.TrashSettings.tiersHelp).type(.body3(.regular), style: .tertiary)
            if store.isVersionsInvalid {
                Text(L10n.TrashSettings.versionsInvalid).type(.body3(.regular), style: .error)
            }
            Text(L10n.TrashSettings.versionsEnvironmentNote).type(.body3(.regular), style: .tertiary)
            Text(L10n.TrashSettings.sharedSpace).type(.body3(.regular), style: .tertiary)
        }
    }

    private func versionField(
        _ title: String,
        _ keyPath: KeyPath<TrashSettingsFeature.VersionsDraft, String>,
        _ field: TrashSettingsFeature.VersionField
    ) -> some View {
        SettingsNumberField(
            title: title,
            text: Binding(
                get: { store.versionsDraft[keyPath: keyPath] },
                set: { store.send(.versionFieldChanged(field, $0)) }
            )
        )
    }

    private var saveRow: some View {
        VStack(spacing: ServerSettingsMetrics.rowSpacing) {
            DSButton(L10n.TrashSettings.saveButton, style: .primary, isLoading: store.isSaving) {
                store.send(.saveTapped)
            }
            .disabled(!store.isSaveEnabled)
            if store.isDirty {
                DSButton(L10n.TrashSettings.discardButton, style: .secondary) {
                    store.send(.discardTapped)
                }
            }
        }
        .padding(.top, .space4)
        .formActionAlignment()
    }

    // MARK: Volumes

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: ServerSettingsMetrics.contentSpacing) {
            VStack(alignment: .leading, spacing: .space8) {
                DSFieldLabel(L10n.TrashSettings.zonesHeader)
                Text(L10n.TrashSettings.zonesSubtitle).type(.body3(.regular), style: .secondary)
            }
            if let zonesError = store.zonesError {
                DSErrorCard(zonesError)
            }
            if store.zones.isEmpty, store.zonesPhase == .loaded {
                DSInfoCard(L10n.TrashSettings.zonesEmpty)
            }
            ForEach(store.zones) { zone in
                zoneCard(zone)
            }
            verificationSummary
            VStack(spacing: ServerSettingsMetrics.rowSpacing) {
                DSButton(L10n.TrashSettings.verify, style: .secondary, isLoading: store.isVerifying) {
                    store.send(.verifyTapped)
                }
                .disabled(store.zones.isEmpty)
                DSButton(L10n.TrashSettings.runMaintenance, style: .secondary, isLoading: store.isMaintaining) {
                    store.send(.maintenanceTapped)
                }
            }
            .formActionAlignment()
        }
    }

    @ViewBuilder
    private var verificationSummary: some View {
        if store.verification != nil {
            if store.totalViolations == 0 {
                DSInfoCard(L10n.TrashSettings.verifyOk)
            } else {
                DSErrorCard(L10n.TrashSettings.verifyIssues(store.totalViolations))
            }
        }
    }

    private func zoneCard(_ zone: TrashZone) -> some View {
        Card {
            VStack(alignment: .leading, spacing: .space4) {
                Text(label(for: zone)).type(.body2(.semibold), style: .primaryOnSurface)
                Text(state(for: zone))
                    .type(.body3(.regular), style: zone.isAvailable ? .secondary : .error)
            }
            VStack(alignment: .leading, spacing: .space8) {
                if zone.isAvailable {
                    DSUsageBar(fraction: zone.usedFraction)
                }
                VStack(alignment: .leading, spacing: .space4) {
                    if zone.isAvailable {
                        Text(L10n.TrashSettings.usage(Self.bytes(zone.heldBytes), budget(for: zone)))
                            .type(.body3(.regular), style: .secondary)
                    }
                    Text(L10n.TrashSettings.zoneItems(zone.itemCount, Self.bytes(zone.usedBytes)))
                        .type(.body3(.regular), style: .tertiary)
                    Text(L10n.TrashSettings.zoneVersions(zone.versionCount, Self.bytes(zone.versionBytes)))
                        .type(.body3(.regular), style: .tertiary)
                }
            }
            VStack(alignment: .leading, spacing: .space4) {
                Text(L10n.TrashSettings.lastPass(lastPass(for: zone)))
                    .type(.body3(.regular), style: .tertiary)
                if let violations = store.verification?.first(where: { $0.zoneID == zone.id })?.violations, !violations.isEmpty {
                    Text(L10n.TrashSettings.zoneProblems(violations.count)).type(.body3(.semibold), style: .error)
                    ForEach(Array(violations.filter { !$0.invariant.isEmpty }.enumerated()), id: \.offset) { _, violation in
                        Text(L10n.TrashSettings.violation(violation.invariant, violation.detail))
                            .type(.body3(.regular), style: .error)
                    }
                }
            }
            if !zone.events.isEmpty {
                VStack(alignment: .leading, spacing: .space8) {
                    DSFieldLabel(L10n.TrashSettings.journalHeader)
                    VStack(alignment: .leading, spacing: .space4) {
                        ForEach(zone.events) { event in
                            Text(TrashEventLabel.text(for: event)).type(.body3(.regular), style: .secondary)
                        }
                    }
                }
            }
        }
    }

    private func label(for zone: TrashZone) -> String {
        switch zone.kind {
        case .personal: L10n.TrashSettings.zoneKindPersonal(zone.name)
        case .userVolume: L10n.TrashSettings.zoneKindUserVolume(zone.name)
        case .volume: zone.name
        }
    }

    private func state(for zone: TrashZone) -> String {
        guard !zone.isAvailable else { return L10n.TrashSettings.available }
        switch zone.reason {
        case "replaced": return L10n.TrashSettings.unavailableReplaced
        case "unreadable": return L10n.TrashSettings.unavailableUnreadable
        default: return L10n.TrashSettings.unavailableMissing
        }
    }

    private func budget(for zone: TrashZone) -> String {
        zone.budgetBytes.map(Self.bytes) ?? L10n.TrashSettings.noBudget
    }

    private func lastPass(for zone: TrashZone) -> String {
        guard let pass = zone.lastPass else { return L10n.TrashSettings.never }
        let when = Self.date(pass.at) ?? L10n.TrashSettings.never
        return L10n.TrashSettings.lastPassPurged(when, pass.purged)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private static func date(_ iso: String?) -> String? {
        iso.flatMap(ServerTimestamp.date(from:))?.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A journal line in words. The server names events with words joined by dashes; one this
/// app has never heard of is shown as its own name.
enum TrashEventLabel {
    static func text(for event: TrashEvent) -> String {
        let name = event.itemName ?? ""
        switch event.kind {
        case "evicted": return L10n.TrashSettings.eventEvicted(name)
        case "adopted": return L10n.TrashSettings.eventAdopted(name)
        case "lost": return L10n.TrashSettings.eventLost(name)
        case "failed": return L10n.TrashSettings.eventFailed(name)
        case "breaker": return L10n.TrashSettings.eventBreaker
        case "forgotten": return L10n.TrashSettings.eventForgotten(name)
        case "version-evicted": return L10n.TrashSettings.eventVersionEvicted(name)
        case "version-failed": return L10n.TrashSettings.eventVersionFailed
        case "version-lost": return L10n.TrashSettings.eventVersionLost
        case "version-too-large": return L10n.TrashSettings.eventVersionTooLarge(name)
        case "versions-breaker": return L10n.TrashSettings.eventVersionsBreaker
        default: return event.kind
        }
    }
}

private extension TrashSettingsFeature.State {
    static func preview(
        zones: [TrashZone] = [],
        verification: [TrashVerification]? = nil,
        retentionText: String? = nil
    ) -> Self {
        var state = TrashSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loadedTrash = TrashSettings()
        state.loadedVersions = VersionsSettings()
        state.trashDraft = .init(TrashSettings())
        state.versionsDraft = .init(VersionsSettings())
        if let retentionText {
            state.trashDraft.retentionText = retentionText
        }
        state.zones = zones
        state.zonesPhase = .loaded
        state.verification = verification
        state.phase = .loaded
        return state
    }
}

private enum PreviewZones {
    static let available = TrashZone(
        id: "z1", name: "Photos", itemCount: 3, usedBytes: 120_000_000, versionCount: 5, versionBytes: 30_000_000,
        budgetBytes: 1_000_000_000, lastPass: TrashPass(at: "2026-11-11T07:00:00.000Z", purged: 2),
        events: [TrashEvent(id: "1", kind: "evicted", itemName: "holiday.mov")]
    )
    static let missing = TrashZone(id: "z2", kind: .personal, name: "alice", isAvailable: false, reason: "missing", itemCount: 1, usedBytes: 4_000)
}

@MainActor
private func trashPreview(_ state: TrashSettingsFeature.State, failing: Bool = false, settings: SystemSettings? = nil) -> some View {
    let zones = state.zones
    return NavigationStack {
        TrashSettingsView(store: Store(initialState: state) { TrashSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in
                if failing {
                    throw FilesClientError.offline
                }
                return settings ?? SystemSettings(trash: TrashSettings(), versions: VersionsSettings())
            }
            $0.filesClient.fetchTrashZones = { _ in zones }
        })
    }
}

#Preview("Volumes") {
    trashPreview(.preview(zones: [PreviewZones.available, PreviewZones.missing]))
}

#Preview("Verification found problems") {
    trashPreview(.preview(
        zones: [PreviewZones.available],
        verification: [TrashVerification(zoneID: "z1", violations: [.init(invariant: "I1", detail: "content missing")])]
    ))
}

#Preview("Invalid input") {
    trashPreview(.preview(zones: [PreviewZones.available], retentionText: "0"))
}

#Preview("No volumes") {
    trashPreview(.preview())
}

#Preview("Failed") {
    var state = TrashSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
    state.phase = .failed("The server could not be reached.")
    return trashPreview(state, failing: true)
}

#Preview("Not an admin") {
    var state = TrashSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
    state.phase = .loaded
    state.isUnavailable = true
    return trashPreview(state, settings: SystemSettings())
}
