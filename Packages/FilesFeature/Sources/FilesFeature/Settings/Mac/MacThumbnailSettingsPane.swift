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
            MacSettingsPane {
                Section {
                    Toggle(isOn: $store.draft.isEnabled.sending(\.enabledChanged)) {
                        MacRowTitle(title: L10n.ThumbnailSettings.enable, subtitle: L10n.ThumbnailSettings.enableHelp)
                    }
                    .accessibilityLabel(L10n.ThumbnailSettings.enable)
                } footer: {
                    MacSectionFooter(L10n.ThumbnailSettings.subtitle)
                }
                Section {
                    numberRow(L10n.ThumbnailSettings.quality, help: L10n.ThumbnailSettings.qualityHelp) {
                        MacNumberStepper(value: store.draft.quality, range: ThumbnailSettings.qualityRange, step: 5) {
                            store.send(.qualityChanged($0))
                        }
                    }
                    numberRow(L10n.ThumbnailSettings.maxDimension, help: L10n.ThumbnailSettings.maxDimensionHelp) {
                        MacNumberStepper(value: store.draft.size, range: ThumbnailSettings.sizeRange, step: 8, unit: "px") {
                            store.send(.sizeChanged($0))
                        }
                    }
                    numberRow(L10n.ThumbnailSettings.concurrency, help: L10n.ThumbnailSettings.concurrencyHelp) {
                        MacNumberStepper(value: store.draft.concurrency, range: ThumbnailSettings.concurrencyRange, step: 1) {
                            store.send(.concurrencyChanged($0))
                        }
                    }
                }
                .disabled(!store.draft.isEnabled)
                if let error = store.errorMessage ?? store.phase.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }

        private func numberRow(_ title: String, help: String, @ViewBuilder control: () -> some View) -> some View {
            LabeledContent {
                control()
            } label: {
                MacRowTitle(title: title, subtitle: help)
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
