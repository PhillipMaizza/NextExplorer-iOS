import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Admin editor for chunked uploads, pushed from the Settings admin section. Mirrors the web
/// client's `SettingsUploads.vue`.
struct UploadSettingsView: View {
    @Bindable var store: StoreOf<UploadSettingsFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.UploadSettings.navigationTitle,
            subtitle: L10n.UploadSettings.subtitle,
            unavailableMessage: L10n.UploadSettings.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.errorMessage,
            isLoadingFirstTime: store.phase == .loading && store.loaded == nil && !store.isUnavailable,
            isBusy: store.isSaving,
            onAppear: { store.send(.onAppear) }
        ) {
            Card {
                DSToggleRow(
                    title: L10n.UploadSettings.chunkedEnable,
                    subtitle: L10n.UploadSettings.chunkedEnableHelp,
                    icon: IconKit.upload,
                    isOn: $store.draft.isChunkedEnabled.sending(\.chunkedChanged)
                )
            }

            Card {
                VStack(alignment: .leading, spacing: ServerSettingsMetrics.rowSpacing) {
                    Stepper(
                        value: Binding(get: { store.chunkSizeMiB }, set: { store.send(.chunkSizeChanged($0)) }),
                        in: UploadSettings.minChunkSizeMiB ... store.maxChunkSizeMiB
                    ) {
                        HStack {
                            Text(L10n.UploadSettings.chunkSize).type(.body2(.regular), style: .primaryOnSurface)
                            Spacer(minLength: ServerSettingsMetrics.rowSpacing)
                            Text(L10n.UploadSettings.chunkSizeValue(store.chunkSizeMiB))
                                .type(.body2(.semibold), style: .primaryOnSurface)
                                .monospacedDigit()
                        }
                    }
                    Text(L10n.UploadSettings.chunkSizeHelp)
                        .type(.body3(.regular), style: .tertiary)
                }
            }
            .opacity(store.draft.isChunkedEnabled ? 1 : ServerSettingsMetrics.disabledOpacity)
            .disabled(!store.draft.isChunkedEnabled)

            Card {
                DSToggleRow(
                    title: L10n.UploadSettings.autoFallback,
                    subtitle: L10n.UploadSettings.autoFallbackHelp,
                    icon: IconKit.retry,
                    isOn: $store.draft.isChunkedAutoFallback.sending(\.autoFallbackChanged)
                )
            }

            DSButton(L10n.UploadSettings.saveButton, style: .primary, isLoading: store.isSaving) {
                store.send(.saveTapped)
            }
            .disabled(!store.isSaveEnabled)
            .padding(.top, .space4)
            .formActionAlignment()
        }
    }
}

#Preview("Chunked") {
    let uploads = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 16 * UploadSettings.bytesPerMiB)
    return NavigationStack {
        UploadSettingsView(store: Store(initialState: {
            var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = uploads
            state.draft = uploads
            state.phase = .loaded
            return state
        }()) { UploadSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(uploads: uploads) }
        })
    }
}

#Preview("Auto fallback, saving") {
    let uploads = UploadSettings(isChunkedAutoFallback: true)
    return NavigationStack {
        UploadSettingsView(store: Store(initialState: {
            var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = uploads
            state.draft = uploads
            state.phase = .loaded
            state.isSaving = true
            return state
        }()) { UploadSettingsFeature() })
    }
}

#Preview("Failed") {
    NavigationStack {
        UploadSettingsView(store: Store(initialState: {
            var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed("The server could not be reached.")
            return state
        }()) { UploadSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in throw FilesClientError.offline }
        })
    }
}

#Preview("Not an admin") {
    NavigationStack {
        UploadSettingsView(store: Store(initialState: {
            var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loaded
            state.isUnavailable = true
            return state
        }()) { UploadSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        })
    }
}
