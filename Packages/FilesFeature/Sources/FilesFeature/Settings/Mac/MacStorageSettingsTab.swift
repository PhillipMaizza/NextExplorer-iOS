#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Storage pane: the local cache, the files kept for offline use, and the server's disks.
    struct MacStorageSettingsTab: View {
        let store: StoreOf<SettingsFeature>
        @AppStorage(AppStorageKeys.preferOfflineMedia) private var preferOfflineMedia = true

        private var progress: OfflineDownloadProgress {
            store.offlineProgress
        }

        var body: some View {
            MacSettingsForm {
                MacSettingsRow(L10n.MacSettings.cache) {
                    HStack {
                        Text(SettingsFormat.byteFormatter.string(fromByteCount: store.cacheSize))
                        Spacer()
                        Button(L10n.Settings.rowClearCache + "…") { store.send(.clearCacheTapped) }
                            .disabled(store.isClearingCache || store.cacheSize == 0)
                    }
                    MacSettingsNote(L10n.Settings.storageFootnoteMac)
                }
                MacSettingsRow(L10n.Offline.sectionTitle) {
                    offlineContent
                    MacSettingsNote(footnote, L10n.Offline.tunnelSpeedNote)
                }
                if store.isVolumeUsageEnabled, !store.serverUsage.isEmpty {
                    MacSettingsRow(L10n.Settings.sectionServerStorage) {
                        ForEach(store.serverUsage) { row in
                            volumeUsage(row)
                        }
                    }
                }
            }
        }

        private func volumeUsage(_ row: SettingsFeature.VolumeUsage) -> some View {
            VStack(alignment: .leading, spacing: .space4) {
                HStack {
                    Text(row.volume.name)
                    Spacer()
                    if let usage = row.usage, usage.isMeaningful {
                        Text(usageCaption(usage))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if row.usage == nil {
                        ProgressView().controlSize(.small)
                    }
                }
                if let usage = row.usage, usage.isMeaningful {
                    ProgressView(value: usage.fraction)
                }
            }
        }

        private func usageCaption(_ usage: StorageUsage) -> String {
            L10n.Settings.serverStorageUsed(
                SettingsFormat.byteFormatter.string(fromByteCount: usage.used),
                SettingsFormat.byteFormatter.string(fromByteCount: usage.capacity)
            )
        }

        @ViewBuilder
        private var offlineContent: some View {
            if progress.isActive {
                MacOfflineProgress(progress: progress) { store.send(.cancelOfflineDownloadTapped) }
            } else {
                HStack {
                    Button(L10n.Offline.settingsRow + "…") { store.send(.offlineDownloadButtonTapped) }
                    if store.offlineSize > 0 {
                        Button(L10n.Offline.manageRow) { store.send(.offlineManageButtonTapped) }
                    }
                }
            }
            if case let .failed(message) = progress.phase {
                Text(message).foregroundStyle(Color.negativeText)
            }
            if !progress.isActive, store.offlineSize > 0 {
                HStack {
                    Button(L10n.Offline.resyncRow) { store.send(.resyncOfflineTapped) }
                    Button(L10n.Offline.removeRow + "…") { store.send(.removeOfflineTapped) }
                }
                Toggle(L10n.Offline.preferOfflineToggle, isOn: $preferOfflineMedia)
                MacSettingsNote(L10n.Offline.preferOfflineSubtitle)
            }
        }

        private var footnote: String {
            if store.offlineSize > 0 {
                return L10n.Offline.available(SettingsFormat.byteFormatter.string(fromByteCount: store.offlineSize))
            }
            return L10n.Offline.footnote
        }
    }

    /// A running offline download: what it is on, how far along, and a way to stop it.
    private struct MacOfflineProgress: View {
        let progress: OfflineDownloadProgress
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(status)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if progress.phase == .preparing {
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: progress.fractionComplete)
                }
                HStack {
                    Text(L10n.Offline.progressCount(progress.currentFileNumber, progress.filesTotal))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button(L10n.Common.cancel, action: onCancel)
                }
            }
        }

        private var status: String {
            if progress.phase == .downloading, !progress.currentName.isEmpty {
                return L10n.Offline.downloadingName(progress.currentName)
            }
            return L10n.Offline.preparing
        }
    }

    #Preview("Storage") {
        MacStorageSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .frame(width: 640, height: 400)
    }
#endif
