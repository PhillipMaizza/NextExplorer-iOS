import ComposableArchitecture
import SwiftUI

/// The server administration screens the Administration page pushes, declared on that page so
/// they stack above it.
struct SettingsAdminDestinations: ViewModifier {
    @Bindable var store: StoreOf<SettingsFeature>

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $store.scope(
                state: \.thumbnailSettings,
                action: \.thumbnailSettings
            )) { thumbnailStore in
                ThumbnailSettingsView(store: thumbnailStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.accessRules,
                action: \.accessRules
            )) { accessRulesStore in
                AccessRulesView(store: accessRulesStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.uploadSettings,
                action: \.uploadSettings
            )) { uploadStore in
                UploadSettingsView(store: uploadStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.ffmpegSettings,
                action: \.ffmpegSettings
            )) { ffmpegStore in
                FFmpegSettingsView(store: ffmpegStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.searchIndexSettings,
                action: \.searchIndexSettings
            )) { searchIndexStore in
                SearchIndexSettingsView(store: searchIndexStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.folderSizeSettings,
                action: \.folderSizeSettings
            )) { folderSizeStore in
                FolderSizeSettingsView(store: folderSizeStore)
            }
            .navigationDestination(item: $store.scope(state: \.activityLog, action: \.activityLog)) { activityStore in
                ActivityLogView(store: activityStore)
            }
            .navigationDestination(item: $store.scope(state: \.trashSettings, action: \.trashSettings)) { trashStore in
                TrashSettingsView(store: trashStore)
            }
            .navigationDestination(item: $store.scope(
                state: \.versionedFiles,
                action: \.versionedFiles
            )) { versionedStore in
                VersionedFilesView(store: versionedStore)
            }
    }
}

#Preview {
    let store = Store(initialState: SettingsFeature.State.preview) { SettingsFeature() }
    NavigationStack {
        SettingsServerAdminSection(store: store)
            .modifier(SettingsAdminDestinations(store: store))
    }
}
