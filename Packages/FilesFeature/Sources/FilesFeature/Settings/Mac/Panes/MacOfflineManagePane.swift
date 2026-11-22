#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    struct MacOfflineManagePane: View {
        let store: StoreOf<OfflineManageFeature>
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            MacSettingsPaneCard(
                title: L10n.Offline.manageTitle,
                subtitle: L10n.Offline.available(FileSizeFormat.string(store.totalBytes))
            ) {
                MacFormPage {
                    MacFormGroup {
                        if store.isEmpty {
                            MacFormRow {
                                Text(L10n.Offline.manageEmpty).foregroundStyle(Color.macChromeSecondary)
                            } control: {
                                EmptyView()
                            }
                        }
                        ForEach(store.usages) { usage in
                            row(usage)
                        }
                    }
                }
            } tools: {
                Button(action: { dismiss() }, label: {
                    Label { Text(L10n.Settings.sectionStorage) } icon: { IconKit.back }
                        .labelStyle(.titleAndIcon)
                })
                .buttonStyle(.macDS(.secondary))
            }
            .navigationTitle(L10n.Offline.manageTitle)
            .toolbar(removing: .title)
            .navigationBarBackButtonHidden()
            .offlineRemovalAlert(
                store.removal,
                onConfirm: { store.send(.removeConfirmed, animation: DSMotion.listDiff) },
                onCancel: { store.send(.removeCancelled) }
            )
            .task { store.send(.onAppear) }
        }

        private func row(_ usage: OfflinePinnedRootUsage) -> some View {
            MacFormRow {
                HStack(spacing: .space12) {
                    MacItemIcon(name: usage.displayName, isDirectory: usage.root.isDirectory)
                    MacRowTitle(title: usage.displayName, subtitle: Self.location(of: usage))
                }
            } control: {
                HStack(spacing: .space16) {
                    Text(FileSizeFormat.string(usage.sizeBytes))
                        .foregroundStyle(Color.macChromeSecondary)
                        .monospacedDigit()
                    Button(L10n.Common.remove, role: .destructive) {
                        store.send(.removeTapped(path: usage.root.path))
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                }
            }
        }
    }

    extension MacOfflineManagePane {
        static func location(of usage: OfflinePinnedRootUsage) -> String {
            let parent = (usage.root.path as NSString).deletingLastPathComponent
            return parent.isEmpty ? L10n.Browse.myFiles : parent
        }
    }

    #Preview("Items") {
        var state = OfflineManageFeature.State()
        state.usages = [
            OfflinePinnedRootUsage(
                root: OfflinePinnedRoot(path: "Documents", isDirectory: true),
                sizeBytes: 45_000_000
            ),
            OfflinePinnedRootUsage(
                root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false),
                sizeBytes: 3_200_000
            ),
        ]
        return MacOfflineManagePane(store: Store(initialState: state) { EmptyReducer() })
            .previewCanvas(.settingsPane)
    }

    #Preview("Empty") {
        MacOfflineManagePane(store: Store(initialState: OfflineManageFeature.State()) { EmptyReducer() })
            .previewCanvas(.settingsPane)
    }
#endif
