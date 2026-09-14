import ComposableArchitecture
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct TipJarFeatureTests {
    private let sample = [
        TipProduct(id: TipProductID.coffee, displayName: "Coffee", displayPrice: "$0.99"),
        TipProduct(id: TipProductID.cake, displayName: "Cake", displayPrice: "$2.99"),
        TipProduct(id: TipProductID.generous, displayName: "Generous", displayPrice: "$4.99"),
    ]

    @Test("products load: task moves to loading then loaded with the sorted tiers")
    func loadSuccess() async {
        let store = TestStore(initialState: TipJarFeature.State()) {
            TipJarFeature()
        } withDependencies: {
            $0.storeKitTipClient.products = { [sample] in sample }
        }
        await store.send(.task) { $0.productsPhase = .loading }
        await store.receive(\.productsResponse) {
            $0.products = self.sample
            $0.productsPhase = .loaded
        }
    }

    @Test("products load failure: task lands on a failed phase with the localized message")
    func loadFailure() async {
        let store = TestStore(initialState: TipJarFeature.State()) {
            TipJarFeature()
        } withDependencies: {
            $0.storeKitTipClient.products = { throw TipError.productNotFound }
        }
        await store.send(.task) { $0.productsPhase = .loading }
        await store.receive(\.productsFailed) {
            $0.productsPhase = .failed(L10n.TipJar.errorLoad)
        }
    }

    @Test("a second task while already loaded does not refetch")
    func noRefetchWhenLoaded() async {
        let store = TestStore(initialState: TipJarFeature.State(productsPhase: .loaded, products: sample)) {
            TipJarFeature()
        }
        await store.send(.task)
    }

    @Test("tip success: the tapped tier shows a spinner, then delegates .tipped")
    func tipSuccess() async {
        let store = TestStore(
            initialState: TipJarFeature.State(productsPhase: .loaded, products: sample)
        ) {
            TipJarFeature()
        } withDependencies: {
            $0.storeKitTipClient.purchase = { _ in .success }
        }
        await store.send(.tipTapped(TipProductID.coffee)) { $0.purchasingID = TipProductID.coffee }
        await store.receive(\.purchaseResponse) { $0.purchasingID = nil }
        await store.receive(\.delegate)
    }

    @Test("tip cancelled: clears the spinner and does not delegate")
    func tipCancelled() async {
        let store = TestStore(
            initialState: TipJarFeature.State(productsPhase: .loaded, products: sample)
        ) {
            TipJarFeature()
        } withDependencies: {
            $0.storeKitTipClient.purchase = { _ in .userCancelled }
        }
        await store.send(.tipTapped(TipProductID.cake)) { $0.purchasingID = TipProductID.cake }
        await store.receive(\.purchaseResponse) { $0.purchasingID = nil }
    }

    @Test("tip failure: surfaces the localized error and clears the spinner")
    func tipFailure() async {
        let store = TestStore(
            initialState: TipJarFeature.State(productsPhase: .loaded, products: sample)
        ) {
            TipJarFeature()
        } withDependencies: {
            $0.storeKitTipClient.purchase = { _ in throw TipError.unverified }
        }
        await store.send(.tipTapped(TipProductID.generous)) { $0.purchasingID = TipProductID.generous }
        await store.receive(\.purchaseFailed) {
            $0.purchasingID = nil
            $0.errorMessage = L10n.TipJar.errorPurchase
        }
    }

    @Test("only one purchase runs at a time: a second tap while one is in flight is ignored")
    func singleInFlight() async {
        let store = TestStore(
            initialState: TipJarFeature.State(
                productsPhase: .loaded, products: sample, purchasingID: TipProductID.coffee
            )
        ) {
            TipJarFeature()
        }
        await store.send(.tipTapped(TipProductID.cake))
    }
}
