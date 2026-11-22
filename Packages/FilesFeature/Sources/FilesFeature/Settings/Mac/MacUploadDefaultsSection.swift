#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    /// The active account's "Shared Files" settings in the Mac Accounts pane.
    struct MacUploadDefaultsSection: View {
        let store: StoreOf<UploadDefaultsFeature>

        var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(L10n.Settings.uploadDefaultsRow) {
                    MacFormRow(L10n.Settings.uploadDefaultsFolder) {
                        MacPopupMenu(L10n.Settings.uploadDefaultsFolder, valueLabel: store.folderTitle) {
                            Button(L10n.ShareUpload.folderChoose + "…") { store.send(.chooseFolderTapped) }
                            if store.hasFolder {
                                Button(L10n.Settings.uploadDefaultsClear) { store.send(.askEachTimeTapped) }
                            }
                        }
                    }
                    MacFormRow(L10n.Settings.uploadDefaultsWithoutAsking) {
                        Toggle(
                            L10n.Settings.uploadDefaultsWithoutAsking,
                            isOn: Binding(
                                get: { store.defaults.shouldUploadWithoutAsking },
                                set: { store.send(.shouldUploadWithoutAskingChanged($0)) }
                            )
                        )
                        .labelsHidden()
                        .disabled(!store.hasFolder)
                    }
                }
                Text(L10n.Settings.uploadDefaultsFooter)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, .space4)
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    #Preview("Shared files") {
        MacFormPage {
            MacUploadDefaultsSection(store: .uploadDefaultsPreview(folder: "Photos/Mac", withoutAsking: true))
        }
        .previewCanvas(.settingsPane)
    }
#endif
