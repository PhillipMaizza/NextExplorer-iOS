import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let rowSpacing: CGFloat = .space4
    static let rowIconSpacing: CGFloat = .space8
    static let rowIconSize: CGFloat = .iconSmall
    static let disabledOpacity: Double = 0.5
    static let sizeStep = 8
    static let qualityStep = 5
    static let concurrencyStep = 1
}

/// Admin-only editor for the server's thumbnail generation config, pushed from the Settings
/// admin section. Mirrors the web client's `SettingsFilesThumbnails.vue`.
struct ThumbnailSettingsView: View {
    @Bindable var store: StoreOf<ThumbnailSettingsFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                Text(L10n.ThumbnailSettings.subtitle)
                    .type(.body3(.regular), style: .secondary)

                if store.isUnavailable {
                    DSErrorCard(L10n.ThumbnailSettings.unavailable)
                } else {
                    formCard

                    if let error = store.errorMessage ?? store.phase.errorMessage {
                        DSErrorCard(error)
                    }

                    DSButton(L10n.ThumbnailSettings.saveButton, style: .primary, isLoading: store.isSaving) {
                        store.send(.saveTapped)
                    }
                    .disabled(!store.isSaveEnabled)
                    .padding(.top, .space4)
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.ThumbnailSettings.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.phase == .loading && store.loaded == nil && !store.isUnavailable {
                ProgressView()
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    private var formCard: some View {
        Card {
            DSToggleRow(
                title: L10n.ThumbnailSettings.enable,
                subtitle: L10n.ThumbnailSettings.enableHelp,
                icon: IconKit.photo,
                isOn: $store.draft.isEnabled.sending(\.enabledChanged)
            )

            VStack(alignment: .leading, spacing: .space16) {
                numericRow(
                    title: L10n.ThumbnailSettings.quality,
                    help: L10n.ThumbnailSettings.qualityHelp,
                    icon: IconKit.sparkle,
                    value: store.draft.quality,
                    unit: nil,
                    range: ThumbnailSettings.qualityRange,
                    step: Metrics.qualityStep,
                    onChange: { store.send(.qualityChanged($0)) }
                )
                numericRow(
                    title: L10n.ThumbnailSettings.maxDimension,
                    help: L10n.ThumbnailSettings.maxDimensionHelp,
                    icon: IconKit.resize,
                    value: store.draft.size,
                    unit: "px",
                    range: ThumbnailSettings.sizeRange,
                    step: Metrics.sizeStep,
                    onChange: { store.send(.sizeChanged($0)) }
                )
                numericRow(
                    title: L10n.ThumbnailSettings.concurrency,
                    help: L10n.ThumbnailSettings.concurrencyHelp,
                    icon: IconKit.speed,
                    value: store.draft.concurrency,
                    unit: nil,
                    range: ThumbnailSettings.concurrencyRange,
                    step: Metrics.concurrencyStep,
                    onChange: { store.send(.concurrencyChanged($0)) }
                )
            }
            .opacity(store.draft.isEnabled ? 1 : Metrics.disabledOpacity)
            .disabled(!store.draft.isEnabled)
        }
    }

    private func numericRow(
        title: String,
        help: String,
        icon: Image,
        value: Int,
        unit: String?,
        range: ClosedRange<Int>,
        step: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            Stepper(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range,
                step: step
            ) {
                HStack(spacing: Metrics.rowIconSpacing) {
                    icon
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    Text(title).type(.body2(.regular), style: .primary(for: .label))
                    Spacer()
                    Text(unit.map { "\(value) \($0)" } ?? "\(value)")
                        .type(.body2(.semibold), style: .primary(for: .label))
                        .monospacedDigit()
                }
            }
            Text(help).type(.body3(.regular), style: .tertiary)
        }
    }
}

private extension ThumbnailSettingsFeature.State {
    static func preview(
        loaded: ThumbnailSettings? = ThumbnailSettings(),
        isLoading: Bool = false,
        error: String? = nil,
        unavailable: Bool = false
    ) -> Self {
        var state = ThumbnailSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = loaded
        state.draft = loaded ?? ThumbnailSettings()
        state.phase = isLoading ? .loading : (loaded != nil || unavailable ? .loaded : .idle)
        state.errorMessage = error
        state.isUnavailable = unavailable
        return state
    }
}

#Preview("Loaded") {
    NavigationStack {
        ThumbnailSettingsView(
            store: Store(initialState: .preview()) { ThumbnailSettingsFeature() }
        )
    }
}

#Preview("Disabled") {
    NavigationStack {
        ThumbnailSettingsView(
            store: Store(initialState: .preview(loaded: ThumbnailSettings(isEnabled: false))) {
                ThumbnailSettingsFeature()
            }
        )
    }
}

#Preview("Not an admin") {
    NavigationStack {
        ThumbnailSettingsView(
            store: Store(initialState: .preview(loaded: nil, unavailable: true)) {
                ThumbnailSettingsFeature()
            }
        )
    }
}
