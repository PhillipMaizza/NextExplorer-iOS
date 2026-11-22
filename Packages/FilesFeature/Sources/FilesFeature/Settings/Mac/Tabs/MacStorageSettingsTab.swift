#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let usageBarHeight: CGFloat = .size12
        static let previewOfflineSizeBytes: Int64 = 48_000_000
    }

    /// The Storage pane: the local cache, the files kept for offline use, and the server's disks.
    struct MacStorageSettingsTab: View {
        let store: StoreOf<SettingsFeature>
        @AppStorage(AppStorageKeys.preferOfflineMedia) private var shouldPreferOfflineMedia = true

        private var progress: OfflineDownloadProgress {
            store.offlineProgress
        }

        private var hasServerUsage: Bool {
            store.isVolumeUsageEnabled && !store.serverUsage.isEmpty
        }

        var body: some View {
            MacFormPage {
                HStack(alignment: .top, spacing: .space24) {
                    VStack(spacing: .space24) {
                        if hasServerUsage {
                            serverStorageGroup
                        }
                        cacheGroup
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: .space8) {
                        offlineGroup
                        MacFormFootnote(L10n.Offline.tunnelSpeedNote)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        private var serverStorageGroup: some View {
            MacFormGroup(L10n.Settings.sectionServerStorage) {
                VStack(alignment: .leading, spacing: .space16) {
                    ForEach(store.serverUsage) { row in
                        volumeUsage(row)
                    }
                }
                .padding(.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func volumeUsage(_ row: SettingsFeature.VolumeUsage) -> some View {
            let isMeaningful = row.usage?.isMeaningful ?? false
            return VStack(alignment: .leading, spacing: .space8) {
                if store.serverUsage.count > 1 || !isMeaningful {
                    Text(row.volume.name).type(.body3(.regular), style: .secondary)
                }
                if let usage = row.usage, isMeaningful {
                    Text(usageCaption(usage))
                        .type(.headline1)
                        .monospacedDigit()
                    DSUsageBar(fraction: usage.fraction, height: Metrics.usageBarHeight)
                } else if row.usage == nil {
                    MacSpinner()
                }
            }
        }

        private func usageCaption(_ usage: StorageUsage) -> String {
            L10n.Settings.serverStorageUsed(
                FileSizeFormat.string(usage.used),
                FileSizeFormat.string(usage.capacity)
            )
        }

        private var cacheGroup: some View {
            MacFormGroup(L10n.MacSettings.cache) {
                MacFormRow {
                    MacRowTitle(title: L10n.MacSettings.cache, subtitle: L10n.Settings.storageFootnoteMac)
                } control: {
                    sizeValue(store.cacheSize)
                }
                MacFormRow {
                    Spacer(minLength: .zero)
                } control: {
                    Button(L10n.Settings.rowClearCache) { store.send(.clearCacheTapped) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(store.clearCachePhase.isRunning || store.cacheSize == 0)
                }
            }
        }

        private var offlineGroup: some View {
            MacFormGroup(L10n.Offline.sectionTitle) {
                MacFormRow {
                    MacRowTitle(title: L10n.Offline.manageTitle, subtitle: L10n.Offline.footnote)
                } control: {
                    sizeValue(store.offlineSize)
                }
                if !progress.isActive, store.offlineSize > 0 {
                    Button { store.send(.offlineManageButtonTapped) } label: {
                        MacFormRow(L10n.Offline.manageRow) {
                            IconKit.chevronRight
                                .imageScale(.small)
                                .foregroundStyle(Color.macChromeSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    MacSwitchRow(
                        L10n.Offline.preferOfflineToggle,
                        help: L10n.Offline.preferOfflineSubtitle,
                        isOn: $shouldPreferOfflineMedia
                    )
                }
                downloadRow
                if case let .failed(message) = progress.phase {
                    MacFormRow {
                        Text(message).foregroundStyle(Color.negativeText)
                    } control: {
                        EmptyView()
                    }
                }
                if !progress.isActive, store.offlineSize > 0 {
                    MacFormRow {
                        HStack(spacing: .space8) {
                            Button(L10n.Offline.resyncRow) { store.send(.resyncOfflineTapped) }
                                .buttonStyle(.macDS(.secondary, size: .small))
                            Button(L10n.ellipsized(L10n.Offline.removeRow), role: .destructive) {
                                store.send(.removeOfflineTapped)
                            }
                            .buttonStyle(.macDS(.secondary, size: .small))
                        }
                    } control: {
                        EmptyView()
                    }
                }
            }
        }

        @ViewBuilder
        private var downloadRow: some View {
            if progress.isActive {
                MacOfflineProgress(progress: progress) { store.send(.cancelOfflineDownloadTapped) }
                    .padding(.horizontal, .space16)
                    .padding(.vertical, .space12)
            } else {
                MacFormRow {
                    VStack(alignment: .leading, spacing: .space8) {
                        Button(L10n.ellipsized(L10n.Offline.settingsRow)) { store.send(.offlineDownloadButtonTapped) }
                            .buttonStyle(.macDS(.secondary, size: .small))
                        if progress.phase == .waitingForNetwork {
                            OfflineWaitingNote(
                                onResync: store.offlineSize > 0 ? { store.send(.resyncOfflineTapped) } : nil
                            )
                        }
                    }
                } control: {
                    EmptyView()
                }
            }
        }

        private func sizeValue(_ bytes: Int64) -> some View {
            Text(FileSizeFormat.string(bytes))
                .type(.body2(.regular), style: .secondary)
                .monospacedDigit()
        }
    }

    /// A running offline download: what it is on, how far along, and a way to stop it.
    private struct MacOfflineProgress: View {
        let progress: OfflineDownloadProgress
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                Text(status)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Group {
                    if progress.phase == .preparing {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: progress.fractionComplete)
                    }
                }
                .tint(Color.accent)
                HStack {
                    Text(L10n.Offline.progressCount(progress.currentFileNumber, progress.filesTotal))
                        .type(.body3(.regular), style: .secondary)
                        .monospacedDigit()
                    Spacer()
                    Button(L10n.Common.cancel, action: onCancel)
                        .buttonStyle(.macDS(.secondary, size: .small))
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
            .previewCanvas(.settingsPane)
    }

    #Preview("Storage: offline files") {
        var state = SettingsFeature.State.macPreview
        state.offlineSize = Metrics.previewOfflineSizeBytes
        return MacStorageSettingsTab(store: Store(initialState: state) { SettingsFeature() })
            .previewCanvas(.settingsWindow)
    }

    #Preview("Storage: offline waiting for network") {
        @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) var progress = OfflineDownloadProgress()
        $progress.withLock { $0.phase = .waitingForNetwork }
        var state = SettingsFeature.State.macPreview
        state.offlineSize = Metrics.previewOfflineSizeBytes
        return MacStorageSettingsTab(store: Store(initialState: state) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
