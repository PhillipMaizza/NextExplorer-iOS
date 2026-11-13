import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconSmall
    static let fullOpacity: Double = 1.0
    static let disabledOpacity: Double = 0.5
    static let progressSpacing: CGFloat = .space8
    static let statusPulseOpacity: Double = 0.55
    static let statusPulseDuration: Double = 1.1
    static let preparingBarHeight: CGFloat = 6
    static let preparingBarOpacity: Double = 0.3
}

/// The Offline section: a row to open the file/folder chooser, a live progress block while a
/// download runs (kept advancing by the session lifetime engine even while the user is elsewhere),
/// and, once idle, how much is available offline with a way to remove it.
struct OfflineSettingsSection: View {
    let store: StoreOf<SettingsFeature>
    let filter: SettingsSearchFilter
    @AppStorage(AppStorageKeys.preferOfflineMedia) private var shouldPreferOfflineMedia = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusPulse = false

    private var progress: OfflineDownloadProgress {
        store.offlineProgress
    }

    var body: some View {
        if filter.anyMatch([
            L10n.Offline.settingsRow,
            L10n.Offline.manageRow,
            L10n.Offline.resyncRow,
            L10n.Offline.preferOfflineToggle,
            L10n.Offline.removeRow,
        ]) {
            Section {
                if filter.matches(L10n.Offline.settingsRow) {
                    VStack(alignment: .leading, spacing: .space4) {
                        DSNavigationRow(
                            title: L10n.Offline.settingsRow,
                            icon: IconKit.download,
                            accessory: .chevron
                        ) {
                            store.send(.offlineDownloadButtonTapped)
                        }
                        .disabled(progress.isActive)
                        .opacity(progress.isActive ? Constants.disabledOpacity : Constants.fullOpacity)
                        if progress.phase == .waitingForNetwork {
                            OfflineWaitingNote(onResync: store
                                .offlineSize > 0 ? { store.send(.resyncOfflineTapped) } : nil)
                        }
                    }
                }

                if progress.isActive {
                    progressRow
                }

                if case let .failed(message) = progress.phase {
                    Text(message)
                        .type(.body3(.regular), style: .error)
                }

                if !progress.isActive, store.offlineSize > 0 {
                    if filter.matches(L10n.Offline.manageRow) {
                        DSNavigationRow(
                            title: L10n.Offline.manageRow,
                            icon: IconKit.cloud,
                            accessory: .detail(FileSizeFormat.string(store.offlineSize))
                        ) {
                            store.send(.offlineManageButtonTapped)
                        }
                    }
                    if filter.matches(L10n.Offline.resyncRow) {
                        DSNavigationRow(
                            title: L10n.Offline.resyncRow,
                            icon: IconKit.retry,
                            accessory: .none
                        ) {
                            store.send(.resyncOfflineTapped)
                        }
                    }
                    if filter.matches(L10n.Offline.preferOfflineToggle) {
                        DSToggleRow(
                            title: L10n.Offline.preferOfflineToggle,
                            subtitle: L10n.Offline.preferOfflineSubtitle,
                            icon: IconKit.play,
                            isOn: $shouldPreferOfflineMedia
                        )
                    }
                    if filter.matches(L10n.Offline.removeRow) {
                        DSNavigationRow(
                            title: L10n.Offline.removeRow,
                            icon: IconKit.delete,
                            accessory: .detail(FileSizeFormat.string(store.offlineSize)),
                            role: .accent
                        ) {
                            store.send(.removeOfflineTapped)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(L10n.Offline.sectionTitle)
            } footer: {
                if !filter.isActive {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(footerText)
                        Text(L10n.Offline.tunnelSpeedNote)
                    }
                    .type(.body3(.regular), style: .tertiary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private var footerText: String {
        if progress.phase == .completed, store.offlineSize > 0 {
            return L10n.Offline.available(FileSizeFormat.string(store.offlineSize))
        }
        return L10n.Offline.footnote
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: Constants.progressSpacing) {
            Text(statusText)
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                // A slow breathing fade while a sync runs, so the row reads as actively working.
                .animation(reduceMotion
                    ? nil
                    : .easeInOut(duration: Constants.statusPulseDuration)
                        .repeatForever(autoreverses: true))
                {
                    $0.opacity(statusPulse ? Constants.statusPulseOpacity : 1)
                }
                .onAppear { statusPulse = true }
            if progress.phase == .preparing {
                // No count yet while we walk the folders: an indeterminate shimmer reads as "working".
                Capsule()
                    .fill(Color.accent.opacity(Constants.preparingBarOpacity))
                    .frame(height: Constants.preparingBarHeight)
                    .shimmering()
            } else {
                ProgressView(value: progress.fractionComplete)
                    .tint(Color.accent)
            }
            HStack {
                Text(L10n.Offline.progressCount(progress.currentFileNumber, progress.filesTotal))
                    .type(.body3(.regular), style: .tertiary)
                    .monospacedDigit()
                Spacer()
                Button {
                    store.send(.cancelOfflineDownloadTapped)
                } label: {
                    Text(L10n.Common.cancel)
                        .type(.label4, style: .link)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, .space4)
    }

    private var statusText: String {
        switch progress.phase {
        case .preparing:
            L10n.Offline.preparing
        case .downloading where !progress.currentName.isEmpty:
            L10n.Offline.downloadingName(progress.currentName)
        default:
            L10n.Offline.preparing
        }
    }
}

private enum PreviewFixture {
    static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    static let user = User(
        id: "preview-user",
        username: "jdoe",
        email: "jane.doe@example.com",
        displayName: "Jane Doe",
        roles: []
    )
    static let offlineSizeBytes: Int64 = 48_000_000
    static let filesTotal = 12
    static let filesDone = 5
}

@MainActor
private func offlinePreviewStore(
    phase: OfflineDownloadProgress.Phase, offlineSize: Int64 = PreviewFixture.offlineSizeBytes
) -> StoreOf<SettingsFeature> {
    @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) var progress = OfflineDownloadProgress()
    $progress.withLock {
        $0.phase = phase
        $0.filesTotal = PreviewFixture.filesTotal
        $0.filesDone = PreviewFixture.filesDone
        $0.unitsDone = Double(PreviewFixture.filesDone)
        $0.currentName = "report.pdf"
    }
    var state = SettingsFeature.State(serverURL: PreviewFixture.serverURL, user: PreviewFixture.user)
    state.offlineSize = offlineSize
    return Store(initialState: state) { SettingsFeature() }
}

#Preview("Offline: idle") {
    List { OfflineSettingsSection(store: offlinePreviewStore(phase: .idle), filter: SettingsSearchFilter(query: "")) }
}

#Preview("Offline: nothing downloaded") {
    List { OfflineSettingsSection(
        store: offlinePreviewStore(phase: .idle, offlineSize: 0),
        filter: SettingsSearchFilter(query: "")
    ) }
}

#Preview("Offline: downloading") {
    List { OfflineSettingsSection(
        store: offlinePreviewStore(phase: .downloading),
        filter: SettingsSearchFilter(query: "")
    ) }
}

#Preview("Offline: waiting for network") {
    List { OfflineSettingsSection(
        store: offlinePreviewStore(phase: .waitingForNetwork),
        filter: SettingsSearchFilter(query: "")
    ) }
}

#Preview("Offline: failed") {
    List { OfflineSettingsSection(
        store: offlinePreviewStore(phase: .failed("The server could not be reached.")),
        filter: SettingsSearchFilter(query: "")
    ) }
}
