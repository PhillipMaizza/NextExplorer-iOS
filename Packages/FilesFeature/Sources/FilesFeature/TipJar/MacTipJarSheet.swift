#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let spacing: CGFloat = .space16
        static let width: CGFloat = 520
    }

    struct MacTipJarSheet: View {
        @Bindable var store: StoreOf<TipJarFeature>
        let onClose: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                VStack(alignment: .leading, spacing: .space8) {
                    Text(L10n.TipJar.title).type(.headline4)
                    Text(L10n.TipJar.explanation)
                        .type(.body2(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
                if let notice = store.noticeMessage {
                    MacNote(notice, kind: .info)
                }
                tiers
                HStack {
                    Spacer(minLength: .zero)
                    Button(L10n.Common.close, action: onClose)
                        .buttonStyle(.macDS(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.space24)
            .frame(width: Metrics.width)
            .background(Color.macCard)
            .task { store.send(.task) }
        }

        @ViewBuilder
        private var tiers: some View {
            switch store.productsPhase {
            case .idle, .loading:
                MacSpinner()
                    .frame(maxWidth: .infinity, minHeight: MacFormMetrics.height(ofRows: TipProductID.all.count))
            case .failed:
                Button(L10n.Common.retry) { store.send(.task) }
                    .buttonStyle(.macDS(.secondary))
            case .loaded:
                MacFormGroup {
                    ForEach(store.products) { tierRow($0) }
                }
            }
        }

        private func tierRow(_ product: TipProduct) -> some View {
            MacFormRow {
                HStack(spacing: .space12) {
                    Text(product.emoji)
                        .type(.headline4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: .space4) {
                        HStack(spacing: .space8) {
                            Text(product.displayName).type(.body2(.semibold))
                            if product.id == TipProductID.featured {
                                MacChip(text: L10n.TipJar.mostPopular, tone: .amber, size: .small)
                            }
                        }
                        Text(Self.note(for: product.id))
                            .type(.body3(.regular))
                            .foregroundStyle(Color.macChromeSecondary)
                    }
                }
                .padding(.vertical, .space8)
            } control: {
                if store.purchasingID == product.id {
                    MacSpinner()
                } else {
                    Button(product.displayPrice) { store.send(.tipTapped(product.id)) }
                        .buttonStyle(.macDS(.primary, size: .small))
                        .disabled(store.purchasingID != nil)
                        .accessibilityLabel(L10n.Common.pair(product.displayName, product.displayPrice))
                }
            }
        }
    }

    extension MacTipJarSheet {
        static func note(for id: String) -> String {
            switch id {
            case TipProductID.coffee: L10n.TipJar.noteCoffee
            case TipProductID.cake: L10n.TipJar.noteCake
            default: L10n.TipJar.noteGenerous
            }
        }
    }

    @MainActor
    private func macTipJarPreview(_ mutate: (inout TipJarFeature.State) -> Void) -> some View {
        var state = TipJarFeature.State()
        mutate(&state)
        return MacTipJarSheet(store: Store(initialState: state) { EmptyReducer() }, onClose: {})
    }

    #Preview("Loaded") {
        macTipJarPreview {
            $0.productsPhase = .loaded
            $0.products = PreviewTips.products
        }
    }

    #Preview("Purchasing") {
        macTipJarPreview {
            $0.productsPhase = .loaded
            $0.products = PreviewTips.products
            $0.purchasingID = TipProductID.cake
        }
    }

    #Preview("Error") {
        macTipJarPreview {
            $0.productsPhase = .loaded
            $0.products = PreviewTips.products
            $0.errorMessage = "Purchase failed. Please try again."
        }
    }

    #Preview("Loading") { macTipJarPreview { $0.productsPhase = .loading } }

    #Preview("Failed load") { macTipJarPreview { $0.productsPhase = .failed("Couldn't load tips.") } }
#endif
