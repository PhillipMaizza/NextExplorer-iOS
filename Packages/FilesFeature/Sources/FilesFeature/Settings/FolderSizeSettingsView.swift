import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Admin editor for how folder sizes are counted and which folders are skipped, pushed from the
/// Settings admin section. Mirrors the web client's `SettingsFolderSize.vue`.
struct FolderSizeSettingsView: View {
    @Bindable var store: StoreOf<FolderSizeSettingsFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.FolderSizeSettings.navigationTitle,
            subtitle: L10n.FolderSizeSettings.subtitle,
            unavailableMessage: L10n.FolderSizeSettings.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.errorMessage,
            isLoadingFirstTime: store.phase == .loading && store.loaded == nil && !store.isUnavailable,
            isBusy: store.isSaving,
            onAppear: { store.send(.onAppear) }
        ) {
            Card(L10n.FolderSizeSettings.running) {
                Text(L10n.FolderSizeSettings.runningHelp)
                    .type(.body3(.regular), style: .tertiary)
                if let lockedBy = store.lockedBy {
                    Text(L10n.FolderSizeSettings.locked(lockedBy))
                        .type(.body3(.regular), style: .tertiary)
                }
                ChoiceRowList(
                    items: FolderSizeMode.allCases,
                    title: { label(for: $0) },
                    isSelected: { store.mode == $0 },
                    isDisabled: store.isModeLocked,
                    edges: .bottom,
                    onSelect: { store.send(.modeChanged($0)) }
                )
            }

            if store.loaded != nil, store.mode == .off {
                FeatureOffNotice(setting: "FOLDER_SIZE_MODE=full", isSwitchable: store.lockedBy == nil)
            }

            ExcludedPathsEditor(
                environmentTitle: L10n.FolderSizeSettings.environment,
                additionalTitle: L10n.FolderSizeSettings.additional,
                emptyTitle: L10n.FolderSizeSettings.none,
                placeholder: L10n.FolderSizeSettings.placeholder,
                addTitle: L10n.FolderSizeSettings.addButton,
                environmentPaths: store.environmentPaths,
                displayedPaths: store.displayedPaths,
                checkedPaths: store.draftPaths,
                newPath: $store.newPath.sending(\.newPathChanged),
                isEnabled: store.mode != .off,
                onAdd: { store.send(.addPathTapped) },
                onToggle: { store.send(.pathToggled($0)) }
            )

            SettingsSaveRow(
                saveTitle: L10n.FolderSizeSettings.saveButton,
                discardTitle: L10n.FolderSizeSettings.discardButton,
                isSaving: store.isSaving,
                isSaveEnabled: store.isSaveEnabled,
                isDirty: store.isDirty,
                onSave: { store.send(.saveTapped) },
                onDiscard: { store.send(.discardTapped) }
            )
        }
    }

    private func label(for mode: FolderSizeMode) -> String {
        switch mode {
        case .off: L10n.FolderSizeSettings.modeOff
        case .shallow: L10n.FolderSizeSettings.modeShallow
        case .full: L10n.FolderSizeSettings.modeFull
        }
    }
}

#Preview("On, with folders") {
    let value = FolderSizeSettings(
        mode: .shallow,
        excluded: ExcludedPaths(paths: ["Backups"], environmentPaths: ["node_modules"])
    )
    return NavigationStack {
        FolderSizeSettingsView(store: Store(initialState: {
            var state = FolderSizeSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = value
            state.draftPaths = value.excluded.paths
            state.phase = .loaded
            return state
        }()) { FolderSizeSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(folderSize: value) }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(folderSizeMode: .shallow) }
        })
    }
}

#Preview("Off") {
    let value = FolderSizeSettings(mode: .off, excluded: ExcludedPaths(paths: ["Backups"]))
    return NavigationStack {
        FolderSizeSettingsView(store: Store(initialState: {
            var state = FolderSizeSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = value
            state.draftPaths = value.excluded.paths
            state.phase = .loaded
            return state
        }()) { FolderSizeSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(folderSize: value) }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(folderSizeMode: .off) }
        })
    }
}

#Preview("Failed") {
    NavigationStack {
        FolderSizeSettingsView(store: Store(initialState: {
            var state = FolderSizeSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed("The server could not be reached.")
            return state
        }()) { FolderSizeSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in throw FilesClientError.offline }
        })
    }
}

#Preview("Not an admin") {
    NavigationStack {
        FolderSizeSettingsView(store: Store(initialState: {
            var state = FolderSizeSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loaded
            state.isUnavailable = true
            return state
        }()) { FolderSizeSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        })
    }
}
