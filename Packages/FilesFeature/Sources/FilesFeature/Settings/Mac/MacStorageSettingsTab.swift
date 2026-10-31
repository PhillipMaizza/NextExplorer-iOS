#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let usageBarWidth: CGFloat = 160
    }

    /// The Storage pane: the local cache, the files kept for offline use, and the server's disks.
    struct MacStorageSettingsTab: View {
        let store: StoreOf<SettingsFeature>
        @AppStorage(AppStorageKeys.preferOfflineMedia) private var shouldPreferOfflineMedia = true

        private var progress: OfflineDownloadProgress {
            store.offlineProgress
        }

        var body: some View {
            MacSettingsPane {
                Section {
                    LabeledContent(L10n.MacSettings.cache) {
                        HStack {
                            Text(FileSizeFormat.string(store.cacheSize))
                                .monospacedDigit()
                            Button(L10n.Settings.rowClearCache + "…") { store.send(.clearCacheTapped) }
                                .disabled(store.isClearingCache || store.cacheSize == 0)
                        }
                    }
                } footer: {
                    MacSectionFooter(L10n.Settings.storageFootnoteMac)
                }
                Section {
                    offlineRows
                } header: {
                    Text(L10n.Offline.sectionTitle)
                } footer: {
                    MacSectionFooter(footnote, L10n.Offline.tunnelSpeedNote)
                }
                if store.isVolumeUsageEnabled, !store.serverUsage.isEmpty {
                    Section(L10n.Settings.sectionServerStorage) {
                        ForEach(store.serverUsage) { row in
                            volumeUsage(row)
                        }
                    }
                }
            }
        }

        private func volumeUsage(_ row: SettingsFeature.VolumeUsage) -> some View {
            LabeledContent(row.volume.name) {
                if let usage = row.usage, usage.isMeaningful {
                    VStack(alignment: .trailing, spacing: .space4) {
                        Text(usageCaption(usage)).monospacedDigit()
                        ProgressView(value: usage.fraction).frame(width: Metrics.usageBarWidth)
                    }
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

        @ViewBuilder
        private var offlineRows: some View {
            if progress.isActive {
                MacOfflineProgress(progress: progress) { store.send(.cancelOfflineDownloadTapped) }
            } else {
                LabeledContent(L10n.Offline.settingsRow) {
                    Button(L10n.Offline.selectionDownload + "…") { store.send(.offlineDownloadButtonTapped) }
                }
            }
            if case let .failed(message) = progress.phase {
                Text(message).foregroundStyle(Color.negativeText)
            }
            if !progress.isActive, store.offlineSize > 0 {
                Toggle(isOn: $shouldPreferOfflineMedia) {
                    MacRowTitle(title: L10n.Offline.preferOfflineToggle, subtitle: L10n.Offline.preferOfflineSubtitle)
                }
                .accessibilityLabel(L10n.Offline.preferOfflineToggle)
                LabeledContent(L10n.Offline.manageTitle) {
                    Text(FileSizeFormat.string(store.offlineSize)).monospacedDigit()
                }
                HStack {
                    Button(L10n.Offline.manageRow) { store.send(.offlineManageButtonTapped) }
                    Button(L10n.Offline.resyncRow) { store.send(.resyncOfflineTapped) }
                    Spacer()
                    Button(L10n.Offline.removeRow + "…", role: .destructive) { store.send(.removeOfflineTapped) }
                }
            }
        }

        private var footnote: String {
            L10n.Offline.footnote
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
            .previewCanvas(.settingsPane)
    }
#endif
