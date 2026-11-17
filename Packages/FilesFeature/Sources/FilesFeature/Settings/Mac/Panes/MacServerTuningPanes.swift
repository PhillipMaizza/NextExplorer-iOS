#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Uploads pane: chunked uploads, the chunk size within the server's ceiling, and the auto
    /// fallback.
    struct MacUploadSettingsPane: View {
        @Bindable var store: StoreOf<UploadSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.UploadSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                save: MacAdminSave(
                    title: L10n.UploadSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled,
                    action: { store.send(.saveTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                Section {
                    Toggle(isOn: $store.draft.isChunkedEnabled.sending(\.chunkedChanged)) {
                        MacRowTitle(
                            title: L10n.UploadSettings.chunkedEnable,
                            subtitle: L10n.UploadSettings.chunkedEnableHelp
                        )
                    }
                    LabeledContent {
                        MacNumberStepper(
                            label: L10n.UploadSettings.chunkSize,
                            value: store.chunkSizeMiB,
                            range: UploadSettings.minChunkSizeMiB ... store.maxChunkSizeMiB,
                            step: 1
                        ) { store.send(.chunkSizeChanged($0)) }
                    } label: {
                        MacRowTitle(title: L10n.UploadSettings.chunkSize, subtitle: L10n.UploadSettings.chunkSizeHelp)
                    }
                    .disabled(!store.draft.isChunkedEnabled)
                } footer: {
                    MacSectionFooter(L10n.UploadSettings.subtitle)
                }
                Section {
                    Toggle(isOn: $store.draft.isChunkedAutoFallback.sending(\.autoFallbackChanged)) {
                        MacRowTitle(
                            title: L10n.UploadSettings.autoFallback,
                            subtitle: L10n.UploadSettings.autoFallbackHelp
                        )
                    }
                }
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }
    }

    /// The FFmpeg pane: the two executables the server uses for media previews and metadata.
    struct MacFFmpegSettingsPane: View {
        @Bindable var store: StoreOf<FFmpegSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.FfmpegSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                save: MacAdminSave(
                    title: L10n.FfmpegSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled,
                    action: { store.send(.saveTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                Section {
                    pathField(
                        L10n.FfmpegSettings.ffmpegPath,
                        L10n.FfmpegSettings.ffmpegPlaceholder,
                        $store.draft.ffmpegPath.sending(\.ffmpegPathChanged)
                    )
                    pathField(
                        L10n.FfmpegSettings.ffprobePath,
                        L10n.FfmpegSettings.ffprobePlaceholder,
                        $store.draft.ffprobePath.sending(\.ffprobePathChanged)
                    )
                } footer: {
                    MacSectionFooter(
                        L10n.FfmpegSettings.subtitle,
                        L10n.FfmpegSettings.containerPathHelp,
                        L10n.FfmpegSettings.defaultHelp
                    )
                }
                if !store.isValid {
                    Text(L10n.FfmpegSettings.invalid).foregroundStyle(Color.negativeText)
                }
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }

        private func pathField(_ title: String, _ placeholder: String, _ text: Binding<String>) -> some View {
            LabeledContent(title) {
                TextField(title, text: text, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .monospaced()
            }
        }
    }

    /// The Search Index pane: the switch, and the folders the index leaves alone.
    struct MacSearchIndexSettingsPane: View {
        @Bindable var store: StoreOf<SearchIndexSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.SearchIndexSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                save: MacAdminSave(
                    title: L10n.SearchIndexSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled,
                    action: { store.send(.saveTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                Section {
                    Toggle(isOn: Binding(get: { store.isEnabled }, set: { store.send(.enabledChanged($0)) })) {
                        MacRowTitle(
                            title: L10n.SearchIndexSettings.running,
                            subtitle: L10n.SearchIndexSettings.runningHelp
                        )
                    }
                    .disabled(store.isSwitchLocked)
                } footer: {
                    if let lockedBy = store.lockedBy {
                        MacSectionFooter(L10n.SearchIndexSettings.locked(lockedBy))
                    } else {
                        MacSectionFooter(L10n.SearchIndexSettings.subtitle)
                    }
                }
                MacExcludedPathsSections(
                    environmentTitle: L10n.SearchIndexSettings.environment,
                    additionalTitle: L10n.SearchIndexSettings.additional,
                    emptyTitle: L10n.SearchIndexSettings.none,
                    placeholder: L10n.SearchIndexSettings.placeholder,
                    addTitle: L10n.SearchIndexSettings.addButton,
                    discardTitle: L10n.SearchIndexSettings.discardButton,
                    environmentPaths: store.environmentPaths,
                    displayedPaths: store.displayedPaths,
                    checkedPaths: store.draftPaths,
                    newPath: $store.newPath.sending(\.newPathChanged),
                    isDirty: store.isDirty,
                    isEnabled: store.isEnabled,
                    onAdd: { store.send(.addPathTapped) },
                    onToggle: { store.send(.pathToggled($0)) },
                    onDiscard: { store.send(.discardTapped) }
                )
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }
    }

    /// The Folder Sizes pane: how far a count goes, and the folders it skips.
    struct MacFolderSizeSettingsPane: View {
        @Bindable var store: StoreOf<FolderSizeSettingsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: store.isUnavailable,
                unavailableMessage: L10n.FolderSizeSettings.unavailable,
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading && store.loaded == nil,
                save: MacAdminSave(
                    title: L10n.FolderSizeSettings.saveButton,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled,
                    action: { store.send(.saveTapped) }
                ),
                onAppear: { store.send(.onAppear) }
            ) {
                Section {
                    Picker(
                        L10n.FolderSizeSettings.running,
                        selection: Binding(get: { store.mode }, set: { store.send(.modeChanged($0)) })
                    ) {
                        ForEach(FolderSizeMode.allCases, id: \.self) { mode in
                            Text(Self.label(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(store.isModeLocked)
                } header: {
                    Text(L10n.FolderSizeSettings.running)
                } footer: {
                    if let lockedBy = store.lockedBy {
                        MacSectionFooter(L10n.FolderSizeSettings.runningHelp, L10n.FolderSizeSettings.locked(lockedBy))
                    } else {
                        MacSectionFooter(L10n.FolderSizeSettings.runningHelp)
                    }
                }
                MacExcludedPathsSections(
                    environmentTitle: L10n.FolderSizeSettings.environment,
                    additionalTitle: L10n.FolderSizeSettings.additional,
                    emptyTitle: L10n.FolderSizeSettings.none,
                    placeholder: L10n.FolderSizeSettings.placeholder,
                    addTitle: L10n.FolderSizeSettings.addButton,
                    discardTitle: L10n.FolderSizeSettings.discardButton,
                    environmentPaths: store.environmentPaths,
                    displayedPaths: store.displayedPaths,
                    checkedPaths: store.draftPaths,
                    newPath: $store.newPath.sending(\.newPathChanged),
                    isDirty: store.isDirty,
                    isEnabled: store.mode != .off,
                    onAdd: { store.send(.addPathTapped) },
                    onToggle: { store.send(.pathToggled($0)) },
                    onDiscard: { store.send(.discardTapped) }
                )
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }

        private static func label(for mode: FolderSizeMode) -> String {
            switch mode {
            case .off: L10n.FolderSizeSettings.modeOff
            case .shallow: L10n.FolderSizeSettings.modeShallow
            case .full: L10n.FolderSizeSettings.modeFull
            }
        }
    }
#endif
