import ComposableArchitecture
import Foundation
import Localization

/// The "buy me a coffee" tip jar. Loads three consumable tiers from StoreKit, buys the tapped
/// one, and shows a short thank you. Purely a gift: nothing is unlocked, so a consumable is
/// finished the moment it completes (see `StoreKitTipClient`).
@Reducer
public struct TipJarFeature {
    @ObservableState
    public struct State: Equatable {
        public var productsPhase: DataPhase
        public var products: [TipProduct]
        /// The tier whose purchase is in flight, so only its price swaps to a spinner. A lone
        /// mutation flag, not a load lifecycle (architecture rule #8).
        public var purchasingID: String?
        public var errorMessage: String?
        /// A neutral note (not an error): shown when a purchase is deferred for approval
        /// (Ask to Buy), so the user isn't left with a spinner that silently vanishes.
        public var noticeMessage: String?

        public init(
            productsPhase: DataPhase = .idle,
            products: [TipProduct] = [],
            purchasingID: String? = nil,
            errorMessage: String? = nil,
            noticeMessage: String? = nil
        ) {
            self.productsPhase = productsPhase
            self.products = products
            self.purchasingID = purchasingID
            self.errorMessage = errorMessage
            self.noticeMessage = noticeMessage
        }
    }

    public enum Action: Sendable {
        case task
        case productsResponse([TipProduct])
        case productsFailed(String)
        case tipTapped(String)
        case purchaseResponse(TipPurchaseOutcome)
        case purchaseFailed(String)
        case delegate(Delegate)

        public enum Delegate: Sendable {
            /// A tip completed. The parent dismisses the sheet and shows the thank you toast.
            case tipped
        }
    }

    @Dependency(\.storeKitTipClient) var client

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.productsPhase.shouldLoadOnAppear else { return .none }
                state.productsPhase = .loading
                let client = client
                return .run { send in
                    do {
                        try await send(.productsResponse(client.products()))
                    } catch {
                        await send(.productsFailed(L10n.TipJar.errorLoad))
                    }
                }

            case let .productsResponse(products):
                state.products = products
                state.productsPhase = .loaded
                return .none

            case let .productsFailed(message):
                state.productsPhase = .failed(message)
                return .none

            case let .tipTapped(id):
                guard state.purchasingID == nil else { return .none }
                state.purchasingID = id
                state.errorMessage = nil
                state.noticeMessage = nil
                let client = client
                return .run { send in
                    do {
                        try await send(.purchaseResponse(client.purchase(id)))
                    } catch {
                        await send(.purchaseFailed(L10n.TipJar.errorPurchase))
                    }
                }

            case let .purchaseResponse(outcome):
                state.purchasingID = nil
                switch outcome {
                case .success:
                    return .send(.delegate(.tipped))
                case .pending:
                    state.noticeMessage = L10n.TipJar.pending
                    return .none
                case .userCancelled:
                    return .none
                }

            case let .purchaseFailed(message):
                state.purchasingID = nil
                state.errorMessage = message
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
