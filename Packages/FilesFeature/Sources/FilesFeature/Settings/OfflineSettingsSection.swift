import AppStorageKeys
import ComposableArchitecture
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
    @AppStorage(AppStorageKeys.preferOfflineMedia) private var preferOfflineMedia = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusPulse = false

    private var progress: OfflineDownloadProgress {
        store.offlineProgress
    }

    var body: some View {
        if filter.anyMatch([L10n.Offline.settingsRow, L10n.Offline.manageRow, L10n.Offline.resyncRow, L10n.Offline.preferOfflineToggle, L10n.Offline.removeRow]) {
            Section {
                if filter.matches(L10n.Offline.settingsRow) {
                    DSNavigationRow(
                        title: L10n.Offline.settingsRow,
                        icon: IconKit.download,
                        accessory: .chevron
                    ) {
                        store.send(.offlineDownloadButtonTapped)
                    }
                    .disabled(progress.isActive)
                    .opacity(progress.isActive ? Constants.disabledOpacity : Constants.fullOpacity)
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
                            accessory: .detail(SettingsFormat.byteFormatter.string(fromByteCount: store.offlineSize))
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
                            isOn: $preferOfflineMedia
                        )
                    }
                    if filter.matches(L10n.Offline.removeRow) {
                        DSNavigationRow(
                            title: L10n.Offline.removeRow,
                            icon: IconKit.delete,
                            accessory: .detail(SettingsFormat.byteFormatter.string(fromByteCount: store.offlineSize)),
                            role: .accent
                        ) {
                            store.send(.removeOfflineTapped)
                        }
                    }
                }
            } header: {
                DSFieldLabel(L10n.Offline.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
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
            return L10n.Offline.available(SettingsFormat.byteFormatter.string(fromByteCount: store.offlineSize))
        }
        return L10n.Offline.footnote
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: Constants.progressSpacing) {
            Text(statusText)
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                // A slow breathing fade while a sync runs, so the row reads as actively working.
                .animation(reduceMotion ? nil : .easeInOut(duration: Constants.statusPulseDuration).repeatForever(autoreverses: true)) {
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
