import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Admin editor for the `ffmpeg` and `ffprobe` paths, pushed from the Settings admin section.
/// Mirrors the web client's `SettingsFfmpeg.vue`.
struct FFmpegSettingsView: View {
    @Bindable var store: StoreOf<FFmpegSettingsFeature>

    var body: some View {
        ServerSettingsPage(
            title: L10n.FfmpegSettings.navigationTitle,
            subtitle: L10n.FfmpegSettings.subtitle,
            unavailableMessage: L10n.FfmpegSettings.unavailable,
            isUnavailable: store.isUnavailable,
            failureMessage: store.phase.errorMessage,
            errorMessage: store.errorMessage,
            isLoadingFirstTime: store.phase == .loading && store.loaded == nil && !store.isUnavailable,
            isBusy: store.isSaving,
            onAppear: { store.send(.onAppear) }
        ) {
            Card {
                Text(L10n.FfmpegSettings.containerPathHelp)
                    .type(.body3(.regular), style: .secondary)
                VStack(alignment: .leading, spacing: .space24) {
                    pathField(
                        title: L10n.FfmpegSettings.ffmpegPath,
                        placeholder: L10n.FfmpegSettings.ffmpegPlaceholder,
                        text: $store.draft.ffmpegPath.sending(\.ffmpegPathChanged)
                    )
                    pathField(
                        title: L10n.FfmpegSettings.ffprobePath,
                        placeholder: L10n.FfmpegSettings.ffprobePlaceholder,
                        text: $store.draft.ffprobePath.sending(\.ffprobePathChanged)
                    )
                }
                if !store.isValid {
                    Text(L10n.FfmpegSettings.invalid)
                        .type(.body3(.regular), style: .error)
                }
                Text(L10n.FfmpegSettings.defaultHelp)
                    .type(.body3(.regular), style: .tertiary)
            }

            DSButton(L10n.FfmpegSettings.saveButton, style: .primary, isLoading: store.isSaving) {
                store.send(.saveTapped)
            }
            .disabled(!store.isSaveEnabled)
            .padding(.top, .space4)
            .formActionAlignment()
        }
    }

    private func pathField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: ServerSettingsMetrics.rowSpacing) {
            DSFieldLabel(title)
            DSTextField(title, text: text, prompt: Text(placeholder))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }
}

#Preview("Paths set") {
    let ffmpeg = FFmpegSettings(ffmpegPath: "/usr/local/bin/ffmpeg", ffprobePath: "/usr/local/bin/ffprobe")
    return NavigationStack {
        FFmpegSettingsView(store: Store(initialState: {
            var state = FFmpegSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = ffmpeg
            state.draft = ffmpeg
            state.phase = .loaded
            return state
        }()) { FFmpegSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(ffmpeg: ffmpeg) }
        })
    }
}

#Preview("Invalid path") {
    let ffmpeg = FFmpegSettings()
    return NavigationStack {
        FFmpegSettingsView(store: Store(initialState: {
            var state = FFmpegSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.loaded = ffmpeg
            state.draft = FFmpegSettings(ffmpegPath: "ffmpeg", ffprobePath: "")
            state.phase = .loaded
            return state
        }()) { FFmpegSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(ffmpeg: ffmpeg) }
        })
    }
}

#Preview("Failed") {
    NavigationStack {
        FFmpegSettingsView(store: Store(initialState: {
            var state = FFmpegSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed("The server could not be reached.")
            return state
        }()) { FFmpegSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in throw FilesClientError.offline }
        })
    }
}

#Preview("Not an admin") {
    NavigationStack {
        FFmpegSettingsView(store: Store(initialState: {
            var state = FFmpegSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loaded
            state.isUnavailable = true
            return state
        }()) { FFmpegSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        })
    }
}
