import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space24
    static let rowSpacing: CGFloat = .space12
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let rowVerticalPadding: CGFloat = .space16
    static let rowHorizontalPadding: CGFloat = .space16
    static let emojiToTitle: CGFloat = .space12
    static let maxHeightFraction: CGFloat = 0.7
}

/// "Buy me a coffee" tip jar: a short note and three consumable tiers, each row `emoji · title
/// —— price`, the tapped row's price swapping to a spinner while StoreKit runs. A gift, nothing
/// is unlocked.
struct TipJarSheet: View {
    @Bindable var store: StoreOf<TipJarFeature>
    let onClose: () -> Void

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                DSSheetHeader(
                    icon: IconKit.logo,
                    title: L10n.TipJar.title,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: onClose
                )

                Text(L10n.TipJar.explanation)
                    .type(.body2(.regular), style: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let error = store.errorMessage {
                    DSErrorCard(error)
                }

                if let notice = store.noticeMessage {
                    Text(notice)
                        .type(.body2(.regular), style: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                content
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
        } footer: {
            EmptyView()
        }
        .task { store.send(.task) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.productsPhase {
        case .idle, .loading:
            DSSpinner()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Metrics.verticalPadding)
        case .failed:
            DSButton(L10n.Common.retry, style: .outline, size: .medium) { store.send(.task) }
        case .loaded:
            VStack(spacing: Metrics.rowSpacing) {
                ForEach(store.products) { product in
                    tierRow(product)
                }
            }
        }
    }

    private func tierRow(_ product: TipProduct) -> some View {
        Button {
            store.send(.tipTapped(product.id))
        } label: {
            HStack(spacing: Metrics.emojiToTitle) {
                Text(product.emoji).type(.body1(.regular))
                Text(product.displayName).type(.body2(.semibold), style: .primaryOnSurface)
                Spacer(minLength: Metrics.rowSpacing)
                if store.purchasingID == product.id {
                    DSSpinner(size: .small)
                } else {
                    Text(product.displayPrice).type(.body2(.semibold), style: .secondary)
                }
            }
            .padding(.vertical, Metrics.rowVerticalPadding)
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .strokeBorder(Color.borderPrimary.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(DSHapticButtonStyle())
        .disabled(store.purchasingID != nil)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }
}

@MainActor
private func tipJarPreview(_ mutate: @Sendable (inout TipJarFeature.State) -> Void = { _ in }) -> some View {
    var state = TipJarFeature.State()
    mutate(&state)
    return Color.clear.sheet(isPresented: .constant(true)) {
        TipJarSheet(
            store: Store(initialState: state) { TipJarFeature() } withDependencies: {
                $0.storeKitTipClient = .previewValue
            },
            onClose: {}
        )
    }
}

private let sampleProducts = [
    TipProduct(id: TipProductID.coffee, displayName: "Coffee", displayPrice: "$0.99"),
    TipProduct(id: TipProductID.cake, displayName: "Cake", displayPrice: "$2.99"),
    TipProduct(id: TipProductID.generous, displayName: "Generous", displayPrice: "$4.99"),
]

#Preview("Loading") { tipJarPreview { $0.productsPhase = .loading } }

#Preview("Loaded") {
    tipJarPreview {
        $0.productsPhase = .loaded
        $0.products = sampleProducts
    }
}

#Preview("Purchasing") {
    tipJarPreview {
        $0.productsPhase = .loaded
        $0.products = sampleProducts
        $0.purchasingID = TipProductID.cake
    }
}

#Preview("Error") {
    tipJarPreview {
        $0.productsPhase = .loaded
        $0.products = sampleProducts
        $0.errorMessage = "Purchase failed. Please try again."
    }
}

#Preview("Failed load") { tipJarPreview { $0.productsPhase = .failed("Couldn't load tips.") } }
