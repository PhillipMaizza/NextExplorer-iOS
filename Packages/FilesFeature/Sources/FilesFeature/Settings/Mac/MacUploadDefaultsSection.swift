#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    /// The active account's "Shared Files" settings in the Mac Accounts pane.
    struct MacUploadDefaultsSection: View {
        let store: StoreOf<UploadDefaultsFeature>

        var body: some View {
            Section {
                LabeledContent(L10n.Settings.uploadDefaultsFolder) {
                    HStack(spacing: .space8) {
                        Text(store.defaults.folderPath.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.Settings.uploadDefaultsFolderNone)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button(L10n.ShareUpload.folderChoose) { store.send(.chooseFolderTapped) }
                        if store.hasFolder {
                            Button(L10n.Settings.uploadDefaultsClear) { store.send(.askEachTimeTapped) }
                        }
                    }
                }
                Toggle(
                    L10n.Settings.uploadDefaultsWithoutAsking,
                    isOn: Binding(
                        get: { store.defaults.uploadsWithoutAsking },
                        set: { store.send(.uploadsWithoutAskingChanged($0)) }
                    )
                )
                .disabled(!store.hasFolder)
            } header: {
                Text(L10n.Settings.uploadDefaultsRow)
            } footer: {
                Text(L10n.Settings.uploadDefaultsFooter).foregroundStyle(.secondary)
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    #Preview("Shared files") {
        Form {
            MacUploadDefaultsSection(store: .uploadDefaultsPreview(folder: "Photos/Mac", withoutAsking: true))
        }
        .formStyle(.grouped)
    }
#endif
