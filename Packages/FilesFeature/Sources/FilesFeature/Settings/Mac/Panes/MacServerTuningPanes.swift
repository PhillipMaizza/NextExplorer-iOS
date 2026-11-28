#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let pathFieldWidth: CGFloat = 340
        static let modeRowHeight: CGFloat = .size64
    }

    struct MacUploadSettingsPane: View {
        @Bindable var store: StoreOf<UploadSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.UploadSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                MacFormGroup {
                    MacSwitchRow(
                        L10n.UploadSettings.chunkedEnable,
                        help: L10n.UploadSettings.chunkedEnableHelp,
                        isOn: $store.draft.isChunkedEnabled.sending(\.chunkedChanged)
                    )
                    MacFormRow {
                        MacFormRowTitle(
                            title: L10n.UploadSettings.chunkSize,
                            subtitle: L10n.UploadSettings.chunkSizeHelp
                        )
                    } control: {
                        MacPopup(
                            L10n.UploadSettings.chunkSize,
                            valueLabel: L10n.UploadSettings.chunkSizeValue(store.chunkSizeMiB),
                            selection: Binding(get: { store.chunkSizeMiB }, set: { store.send(.chunkSizeChanged($0)) })
                        ) {
                            ForEach(store.chunkSizeOptions, id: \.self) { mib in
                                Text(L10n.UploadSettings.chunkSizeValue(mib)).tag(mib)
                            }
                        }
                    }
                    .disabled(!store.draft.isChunkedEnabled)
                    MacSwitchRow(
                        L10n.UploadSettings.autoFallback,
                        help: L10n.UploadSettings.autoFallbackHelp,
                        isOn: $store.draft.isChunkedAutoFallback.sending(\.autoFallbackChanged)
                    )
                }
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
            }
            .disabled(store.isSaving)
        }
    }

    struct MacFFmpegSettingsPane: View {
        @Bindable var store: StoreOf<FFmpegSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.FfmpegSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroup {
                        pathRow(
                            L10n.FfmpegSettings.ffmpegPath,
                            L10n.FfmpegSettings.ffmpegPlaceholder,
                            $store.draft.ffmpegPath.sending(\.ffmpegPathChanged)
                        )
                        pathRow(
                            L10n.FfmpegSettings.ffprobePath,
                            L10n.FfmpegSettings.ffprobePlaceholder,
                            $store.draft.ffprobePath.sending(\.ffprobePathChanged)
                        )
                    }
                    MacFormFootnote(L10n.FfmpegSettings.containerPathHelp, L10n.FfmpegSettings.defaultHelp)
                }
                if !store.isValid {
                    MacNote(L10n.FfmpegSettings.invalid, kind: .error)
                }
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
            }
            .disabled(store.isSaving)
        }

        private func pathRow(_ title: String, _ placeholder: String, _ text: Binding<String>) -> some View {
            MacFormRow(title) {
                MacTextField(title, text: text, prompt: placeholder)
                    .autocorrectionDisabled()
                    .monospaced()
                    .frame(width: Metrics.pathFieldWidth)
            }
        }
    }

    struct MacSearchIndexSettingsPane: View {
        @Bindable var store: StoreOf<SearchIndexSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.SearchIndexSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroup {
                        MacSwitchRow(
                            L10n.SearchIndexSettings.running,
                            help: L10n.SearchIndexSettings.runningHelp,
                            isOn: Binding(get: { store.isEnabled }, set: { store.send(.choiceChanged($0)) })
                        )
                        .disabled(store.isChoiceLocked)
                    }
                    if let lockedBy = store.lockedBy {
                        MacFormFootnote(L10n.SearchIndexSettings.locked(lockedBy))
                    }
                }
                MacExcludedPathsGroups(
                    environmentTitle: L10n.SearchIndexSettings.environment,
                    additionalTitle: L10n.SearchIndexSettings.additional,
                    emptyTitle: L10n.SearchIndexSettings.none,
                    placeholder: L10n.SearchIndexSettings.placeholder,
                    addTitle: L10n.SearchIndexSettings.addButton,
                    environmentPaths: store.environmentPaths,
                    displayedPaths: store.displayedPaths,
                    checkedPaths: store.draftPaths,
                    newPath: $store.newPath.sending(\.newPathChanged),
                    isAddEnabled: store.isAddEnabled,
                    isEnabled: store.isEnabled,
                    onAdd: { store.send(.addPathTapped, animation: DSMotion.listDiff) },
                    onToggle: { store.send(.pathToggled($0), animation: DSMotion.stateFade) }
                )
                if let error = store.newPathError ?? store.errorMessage {
                    MacNote(error, kind: .error)
                }
            }
            .disabled(store.isSaving)
        }
    }

    struct MacFolderSizeSettingsPane: View {
        @Bindable var store: StoreOf<FolderSizeSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.FolderSizeSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                onAppear: { store.send(.onAppear) }
            ) {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroup {
                        MacFormRow {
                            MacFormRowTitle(
                                title: L10n.FolderSizeSettings.running,
                                subtitle: L10n.FolderSizeSettings.runningHelp
                            )
                        } control: {
                            MacSegmentedPicker(
                                L10n.FolderSizeSettings.running,
                                options: FolderSizeMode.allCases,
                                selection: Binding(get: { store.mode }, set: { store.send(.choiceChanged($0)) })
                            ) { Self.label(for: $0) }
                                .disabled(store.isChoiceLocked)
                        }
                        .frame(minHeight: Metrics.modeRowHeight)
                    }
                    if let lockedBy = store.lockedBy {
                        MacFormFootnote(L10n.FolderSizeSettings.locked(lockedBy))
                    }
                }
                MacExcludedPathsGroups(
                    environmentTitle: L10n.FolderSizeSettings.environment,
                    additionalTitle: L10n.FolderSizeSettings.additional,
                    emptyTitle: L10n.FolderSizeSettings.none,
                    placeholder: L10n.FolderSizeSettings.placeholder,
                    addTitle: L10n.FolderSizeSettings.addButton,
                    environmentPaths: store.environmentPaths,
                    displayedPaths: store.displayedPaths,
                    checkedPaths: store.draftPaths,
                    newPath: $store.newPath.sending(\.newPathChanged),
                    isAddEnabled: store.isAddEnabled,
                    isEnabled: store.mode != .off,
                    onAdd: { store.send(.addPathTapped, animation: DSMotion.listDiff) },
                    onToggle: { store.send(.pathToggled($0), animation: DSMotion.stateFade) }
                )
                if let error = store.newPathError ?? store.errorMessage {
                    MacNote(error, kind: .error)
                }
            }
            .disabled(store.isSaving)
        }

        private static func label(for mode: FolderSizeMode) -> String {
            switch mode {
            case .off: L10n.FolderSizeSettings.modeOff
            case .shallow: L10n.FolderSizeSettings.modeShallow
            case .full: L10n.FolderSizeSettings.modeFull
            }
        }
    }

    #Preview("Uploads") {
        let uploads = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 16 * UploadSettings.bytesPerMiB)
        var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loaded = uploads
        state.draft = uploads
        state.phase = .loaded
        return MacUploadSettingsPane(store: Store(initialState: state) { UploadSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(uploads: uploads) }
        })
    }

    #Preview("Uploads loading") {
        var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.phase = .loading
        return MacUploadSettingsPane(store: Store(initialState: state) { EmptyReducer() })
    }

    #Preview("Uploads failed") {
        var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.phase = .failed(L10n.Common.retry)
        return MacUploadSettingsPane(store: Store(initialState: state) { EmptyReducer() })
    }

    #Preview("Uploads unavailable") {
        var state = UploadSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.isUnavailable = true
        return MacUploadSettingsPane(store: Store(initialState: state) { EmptyReducer() })
    }

    #Preview("FFmpeg") {
        let ffmpeg = FFmpegSettings(ffmpegPath: "/usr/local/bin/ffmpeg", ffprobePath: "/usr/local/bin/ffprobe")
        var state = FFmpegSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loaded = ffmpeg
        state.draft = ffmpeg
        state.phase = .loaded
        return MacFFmpegSettingsPane(store: Store(initialState: state) { FFmpegSettingsFeature() } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(ffmpeg: ffmpeg) }
        })
    }

    #Preview("Search index") {
        let value = SearchIndexSettings(
            isEnabled: true,
            excluded: ExcludedPaths(paths: ["Backups", "tmp/cache"], environmentPaths: ["node_modules"])
        )
        var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loaded = value
        state.draftPaths = value.excluded.paths
        state.phase = .loaded
        return MacSearchIndexSettingsPane(store: Store(initialState: state) {
            SearchIndexSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(searchIndex: value) }
        })
    }

    #Preview("Search index, path outside the volumes") {
        let value = SearchIndexSettings(isEnabled: true, excluded: ExcludedPaths(paths: ["Backups"]))
        var state = SearchIndexSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loaded = value
        state.draftPaths = value.excluded.paths
        state.newPath = "../Backups"
        state.phase = .loaded
        return MacSearchIndexSettingsPane(store: Store(initialState: state) {
            SearchIndexSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(searchIndex: value) }
        })
    }

    #Preview("Folder sizes") {
        let value = FolderSizeSettings(
            mode: .shallow,
            excluded: ExcludedPaths(paths: ["Backups"], environmentPaths: ["node_modules"])
        )
        var state = FolderSizeSettingsFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.loaded = value
        state.draftPaths = value.excluded.paths
        state.phase = .loaded
        return MacFolderSizeSettingsPane(store: Store(initialState: state) {
            FolderSizeSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(folderSize: value) }
        })
    }
#endif
