import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// "Shared Files": the folder files shared from other apps start in, and Upload Without Asking.
struct SettingsUploadDefaultsSection: View {
    let store: StoreOf<UploadDefaultsFeature>
    let filter: SettingsSearchFilter

    var body: some View {
        if filter.anyMatch([
            L10n.Settings.uploadDefaultsRow,
            L10n.Settings.uploadDefaultsFolder,
            L10n.Settings.uploadDefaultsWithoutAsking,
        ]) {
            Section {
                DSNavigationRow(
                    title: L10n.Settings.uploadDefaultsFolder,
                    icon: IconKit.folder,
                    accessory: .detail(store.folderTitle)
                ) {
                    store.send(.chooseFolderTapped)
                }
                DSToggleRow(
                    title: L10n.Settings.uploadDefaultsWithoutAsking,
                    icon: IconKit.upload,
                    isOn: Binding(
                        get: { store.defaults.shouldUploadWithoutAsking },
                        set: { store.send(.shouldUploadWithoutAskingChanged($0)) }
                    )
                )
                .disabled(!store.hasFolder)
                if store.hasFolder {
                    Button(L10n.Settings.uploadDefaultsClear) { store.send(.askEachTimeTapped) }
                        .type(.body2(.regular), style: .secondary)
                }
            } header: {
                SettingsSectionHeader(L10n.Settings.uploadDefaultsRow)
            } footer: {
                Text(L10n.Settings.uploadDefaultsFooter).type(.body3(.regular), style: .secondary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

#Preview("Ask each time") {
    List {
        SettingsUploadDefaultsSection(store: .uploadDefaultsPreview(), filter: SettingsSearchFilter(query: ""))
    }
}

#Preview("Default folder, without asking") {
    List {
        SettingsUploadDefaultsSection(
            store: .uploadDefaultsPreview(folder: "Photos/Phone", withoutAsking: true),
            filter: SettingsSearchFilter(query: "")
        )
    }
}

extension StoreOf<UploadDefaultsFeature> {
    static func uploadDefaultsPreview(
        folder: String? = nil,
        withoutAsking: Bool = false
    ) -> StoreOf<UploadDefaultsFeature> {
        var state = UploadDefaultsFeature.State(
            serverURL: URL(string: "https://files.example.com")!,
            accountID: "preview"
        )
        state.defaults = .init(folderPath: folder, shouldUploadWithoutAsking: withoutAsking)
        return Store(initialState: state) { EmptyReducer() }
    }
}
