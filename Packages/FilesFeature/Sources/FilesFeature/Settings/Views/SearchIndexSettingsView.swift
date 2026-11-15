import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Admin editor for the search index switch and its excluded folders, pushed from the Settings
/// admin section. Mirrors the web client's `SettingsSearchIndex.vue`.
struct SearchIndexSettingsView: View {
    @Bindable var store: StoreOf<SearchIndexSettingsFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.SearchIndexSettings.navigationTitle,
            subtitle: L10n.SearchIndexSettings.subtitle,
            unavailableMessage: L10n.SearchIndexSettings.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.errorMessage,
            isLoadingFirstTime: store.phase == .loading && store.loaded == nil && !store.isUnavailable,
            isBusy: store.isSaving,
            onAppear: { store.send(.onAppear) }
        ) {
            Card {
                DSToggleRow(
                    title: L10n.SearchIndexSettings.running,
                    subtitle: L10n.SearchIndexSettings.runningHelp,
                    icon: IconKit.search,
                    isOn: Binding(get: { store.isEnabled }, set: { store.send(.enabledChanged($0)) })
                )
                .disabled(store.isSwitchLocked)
                if let lockedBy = store.lockedBy {
                    Text(L10n.SearchIndexSettings.locked(lockedBy))
                        .type(.body3(.regular), style: .tertiary)
                }
            }

            if store.loaded != nil, !store.isEnabled {
                FeatureOffNotice(setting: "SEARCH_INDEX=true", isSwitchable: store.lockedBy == nil)
            }

            ExcludedPathsEditor(
                environmentTitle: L10n.SearchIndexSettings.environment,
                additionalTitle: L10n.SearchIndexSettings.additional,
                emptyTitle: L10n.SearchIndexSettings.none,
                placeholder: L10n.SearchIndexSettings.placeholder,
                addTitle: L10n.SearchIndexSettings.addButton,
                environmentPaths: store.environmentPaths,
                displayedPaths: store.displayedPaths,
                checkedPaths: store.draftPaths,
                newPath: $store.newPath.sending(\.newPathChanged),
                isEnabled: store.isEnabled,
                onAdd: { store.send(.addPathTapped) },
                onToggle: { store.send(.pathToggled($0)) }
            )

            SettingsSaveRow(
                saveTitle: L10n.SearchIndexSettings.saveButton,
                discardTitle: L10n.SearchIndexSettings.discardButton,
                isSaving: store.isSaving,
                isSaveEnabled: store.isSaveEnabled,
                isDirty: store.isDirty,
                onSave: { store.send(.saveTapped) },
                onDiscard: { store.send(.discardTapped) }
            )
        }
    }
}

#Preview("On, with folders") {
    let value = SearchIndexSettings(
        isEnabled: true,
        excluded: ExcludedPaths(paths: ["Backups", "tmp/cache"], environmentPaths: ["node_modules"])
    )
    return NavigationStack {
        SearchIndexSettingsView(store: Store(initialState: {
            var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = value
            state.draftPaths = value.excluded.paths
            state.phase = .loaded
            return state
        }()) { SearchIndexSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(searchIndex: value) }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isSearchIndexEnabled: true) }
        })
    }
}

#Preview("Off") {
    let value = SearchIndexSettings(isEnabled: false, excluded: ExcludedPaths(paths: ["Backups"]))
    return NavigationStack {
        SearchIndexSettingsView(store: Store(initialState: {
            var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = value
            state.draftPaths = value.excluded.paths
            state.phase = .loaded
            return state
        }()) { SearchIndexSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(searchIndex: value) }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isSearchIndexEnabled: false) }
        })
    }
}

#Preview("Failed") {
    NavigationStack {
        SearchIndexSettingsView(store: Store(initialState: {
            var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed("The server could not be reached.")
            return state
        }()) { SearchIndexSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in throw FilesClientError.offline }
        })
    }
}

#Preview("Not an admin") {
    NavigationStack {
        SearchIndexSettingsView(store: Store(initialState: {
            var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loaded
            state.isUnavailable = true
            return state
        }()) { SearchIndexSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        })
    }
}
