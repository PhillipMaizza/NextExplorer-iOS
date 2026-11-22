#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sizeStep = 8
        static let qualityStep = 5
        static let concurrencyStep = 1
        static let qualityRowHeight: CGFloat = .size64
        static let qualityValueWidth: CGFloat = .size32
    }

    struct MacThumbnailSettingsPane: View {
        @Bindable var store: StoreOf<ThumbnailSettingsFeature>

        var body: some View {
            MacFormPage {
                if store.isUnavailable {
                    MacNote(L10n.ThumbnailSettings.unavailable, kind: .info)
                } else if store.phase == .loading, store.loaded == nil {
                    MacSpinner()
                        .frame(maxWidth: .infinity)
                } else {
                    settingsGroup
                    if let error = store.errorMessage ?? store.phase.errorMessage {
                        MacNote(error, kind: .error)
                    }
                }
            }
            .disabled(store.isSaving)
            .onAppear { store.send(.onAppear) }
        }

        private var settingsGroup: some View {
            MacFormGroup {
                MacSwitchRow(
                    L10n.ThumbnailSettings.enable,
                    help: L10n.ThumbnailSettings.enableHelp,
                    isOn: $store.draft.isEnabled.sending(\.enabledChanged)
                )
                Group {
                    MacFormRow {
                        MacRowTitle(title: L10n.ThumbnailSettings.quality, subtitle: L10n.ThumbnailSettings.qualityHelp)
                    } control: {
                        HStack(spacing: .space12) {
                            MacSlider(
                                label: L10n.ThumbnailSettings.quality,
                                value: store.draft.quality,
                                range: ThumbnailSettings.qualityRange,
                                step: Metrics.qualityStep
                            ) {
                                store.send(.qualityChanged($0))
                            }
                            Text(store.draft.quality, format: .number)
                                .type(.body2(.regular), style: .secondary)
                                .monospacedDigit()
                                .frame(width: Metrics.qualityValueWidth, alignment: .trailing)
                        }
                    }
                    .frame(minHeight: Metrics.qualityRowHeight)
                    MacStepperRow(
                        L10n.ThumbnailSettings.maxDimension,
                        help: L10n.ThumbnailSettings.maxDimensionHelp,
                        value: store.draft.size,
                        range: ThumbnailSettings.sizeRange,
                        step: Metrics.sizeStep
                    ) { store.send(.sizeChanged($0)) }
                    MacStepperRow(
                        L10n.ThumbnailSettings.concurrency,
                        help: L10n.ThumbnailSettings.concurrencyHelp,
                        value: store.draft.concurrency,
                        range: ThumbnailSettings.concurrencyRange,
                        step: Metrics.concurrencyStep
                    ) { store.send(.concurrencyChanged($0)) }
                }
                .disabled(!store.draft.isEnabled)
            }
        }
    }

    #Preview("Thumbnails") {
        var state = ThumbnailSettingsFeature
            .State(serverURL: URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/"))
        state.loaded = ThumbnailSettings()
        state.draft = ThumbnailSettings()
        state.phase = .loaded
        return MacThumbnailSettingsPane(store: Store(initialState: state) { ThumbnailSettingsFeature() })
            .previewCanvas(.settingsWindow)
    }
#endif
