#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacSettingsHeaderTools: View {
        let store: StoreOf<SettingsFeature>
        let category: MacSettingsCategory

        var body: some View {
            switch category {
            case .accounts:
                Button(L10n.MacSettings.addAccount) { store.send(.addAccountTapped) }
                    .buttonStyle(.macDS(.secondary))
                    .disabled(store.isSigningOut)
            case .apiTokens:
                if let tokens = store.scope(state: \.apiTokens, action: \.apiTokens.presented) {
                    MacAPITokensNewButton(store: tokens)
                }
            case .server:
                if let server = store.scope(state: \.serverDetails, action: \.serverDetails.presented) {
                    MacPaneSaveButton(
                        title: L10n.ServerDetails.updateButton,
                        isSaving: server.isSaving,
                        isEnabled: server.isSaveEnabled
                    ) { server.send(.updateTapped) }
                }
            case .thumbnails:
                if let thumbnails = store.scope(state: \.thumbnailSettings, action: \.thumbnailSettings.presented),
                   !thumbnails.isUnavailable
                {
                    MacPaneSaveButton(
                        title: L10n.ThumbnailSettings.saveButton,
                        isSaving: thumbnails.isSaving,
                        isEnabled: thumbnails.isSaveEnabled
                    ) { thumbnails.send(.saveTapped) }
                }
            case .accessRules:
                if let rules = store.scope(state: \.accessRules, action: \.accessRules.presented),
                   !rules.isUnavailable
                {
                    HStack(spacing: .space8) {
                        Button(L10n.AccessRules.addRule) { rules.send(.addRuleTapped, animation: DSMotion.listDiff) }
                            .buttonStyle(.macDS(.secondary))
                            .disabled(rules.isSaving)
                        MacPaneSaveButton(
                            title: L10n.AccessRules.saveButton,
                            isSaving: rules.isSaving,
                            isEnabled: rules.isSaveEnabled
                        ) { rules.send(.saveTapped) }
                    }
                }
            case .uploads:
                if let uploads = store.scope(state: \.uploadSettings, action: \.uploadSettings.presented),
                   !uploads.isUnavailable
                {
                    MacPaneSaveButton(
                        title: L10n.UploadSettings.saveButton,
                        isSaving: uploads.isSaving,
                        isEnabled: uploads.isSaveEnabled
                    ) { uploads.send(.saveTapped) }
                }
            case .ffmpeg:
                if let ffmpeg = store.scope(state: \.ffmpegSettings, action: \.ffmpegSettings.presented),
                   !ffmpeg.isUnavailable
                {
                    MacPaneSaveButton(
                        title: L10n.FfmpegSettings.saveButton,
                        isSaving: ffmpeg.isSaving,
                        isEnabled: ffmpeg.isSaveEnabled
                    ) { ffmpeg.send(.saveTapped) }
                }
            case .searchIndex:
                if let search = store.scope(state: \.searchIndexSettings, action: \.searchIndexSettings.presented),
                   !search.isUnavailable
                {
                    excludedPathsTools(
                        discardTitle: L10n.SearchIndexSettings.discardButton,
                        saveTitle: L10n.SearchIndexSettings.saveButton,
                        store: search
                    )
                }
            case .folderSize:
                if let sizes = store.scope(state: \.folderSizeSettings, action: \.folderSizeSettings.presented),
                   !sizes.isUnavailable
                {
                    excludedPathsTools(
                        discardTitle: L10n.FolderSizeSettings.discardButton,
                        saveTitle: L10n.FolderSizeSettings.saveButton,
                        store: sizes
                    )
                }
            case .activity:
                if let activity = store.scope(state: \.activityLog, action: \.activityLog.presented) {
                    MacActivityLogHeaderButtons(store: activity)
                }
            case .users:
                if let users = store.scope(state: \.userManagement, action: \.userManagement.presented) {
                    Button { users.send(.createUserTapped) } label: {
                        Label { Text(L10n.ellipsized(L10n.UserManagement.createUser)) } icon: { IconKit.plus }
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.macDS(.primary))
                }
            case .trash:
                if let trash = store.scope(state: \.trashSettings, action: \.trashSettings.presented),
                   !trash.isUnavailable
                {
                    MacTrashSettingsTools(store: trash)
                }
            case .general, .storage, .serverTools, .versions, .about:
                EmptyView()
            }
        }

        private func excludedPathsTools(
            discardTitle: String,
            saveTitle: String,
            store: StoreOf<ExcludedPathsSettingsFeature<some ExcludedPathsSection>>
        ) -> some View {
            HStack(spacing: .space8) {
                Button(discardTitle) { store.send(.discardTapped) }
                    .buttonStyle(.macDS(.secondary))
                    .disabled(!store.isDirty || store.isSaving)
                MacPaneSaveButton(
                    title: saveTitle,
                    isSaving: store.isSaving,
                    isEnabled: store.isSaveEnabled
                ) { store.send(.saveTapped) }
            }
        }
    }

    #Preview("Header tools") {
        let store = StoreOf<SettingsFeature>(initialState: .macPreview) { EmptyReducer() }
        VStack(spacing: .space16) {
            MacSettingsHeaderTools(store: store, category: .accounts)
            MacSettingsHeaderTools(store: store, category: .general)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
