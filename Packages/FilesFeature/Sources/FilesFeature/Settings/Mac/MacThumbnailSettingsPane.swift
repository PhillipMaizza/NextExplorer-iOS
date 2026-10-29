#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Thumbnails pane: the server's thumbnail generation, edited in place and saved with
    /// the button under the form.
    struct MacThumbnailSettingsPane: View {
        @Bindable var store: StoreOf<ThumbnailSettingsFeature>

        var body: some View {
            Group {
                if store.isUnavailable {
                    MacSettingsForm { MacSettingsNote(L10n.ThumbnailSettings.unavailable) }
                } else {
                    form.macSettingsSaveBar(
                        L10n.ThumbnailSettings.saveButton,
                        isSaving: store.isSaving,
                        isEnabled: store.isSaveEnabled
                    ) { store.send(.saveTapped) }
                }
            }
            .overlay {
                if store.phase == .loading, store.loaded == nil, !store.isUnavailable {
                    ProgressView()
                }
            }
            .onAppear { store.send(.onAppear) }
        }

        private var form: some View {
            MacSettingsForm {
                MacSettingsRow(L10n.ThumbnailSettings.navigationTitle) {
                    Toggle(L10n.ThumbnailSettings.enable, isOn: $store.draft.isEnabled.sending(\.enabledChanged))
                    MacSettingsNote(L10n.ThumbnailSettings.subtitle, L10n.ThumbnailSettings.enableHelp)
                }
                Group {
                    MacSettingsRow(L10n.ThumbnailSettings.quality) {
                        MacNumberStepper(value: store.draft.quality, range: ThumbnailSettings.qualityRange, step: 5) {
                            store.send(.qualityChanged($0))
                        }
                        MacSettingsNote(L10n.ThumbnailSettings.qualityHelp)
                    }
                    MacSettingsRow(L10n.ThumbnailSettings.maxDimension) {
                        MacNumberStepper(value: store.draft.size, range: ThumbnailSettings.sizeRange, step: 8, unit: "px") {
                            store.send(.sizeChanged($0))
                        }
                        MacSettingsNote(L10n.ThumbnailSettings.maxDimensionHelp)
                    }
                    MacSettingsRow(L10n.ThumbnailSettings.concurrency) {
                        MacNumberStepper(value: store.draft.concurrency, range: ThumbnailSettings.concurrencyRange, step: 1) {
                            store.send(.concurrencyChanged($0))
                        }
                        MacSettingsNote(L10n.ThumbnailSettings.concurrencyHelp)
                    }
                }
                .disabled(!store.draft.isEnabled)
                if let error = store.errorMessage ?? store.phase.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }
    }

    #Preview("Thumbnails") {
        var state = ThumbnailSettingsFeature.State(serverURL: URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/"))
        state.loaded = ThumbnailSettings()
        state.draft = ThumbnailSettings()
        state.phase = .loaded
        return MacThumbnailSettingsPane(store: Store(initialState: state) { ThumbnailSettingsFeature() })
            .frame(width: 580, height: 480)
    }
#endif
