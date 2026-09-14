import ComposableArchitecture
import DependenciesMacros
import Foundation
import StoreKit

/// The three consumable tip products. IDs must match the App Store Connect products and the
/// bundled `TipJar.storekit` config used on the simulator.
public enum TipProductID {
    public static let coffee = "com.phillipmaizza.nextexplorer.tip.coffee"
    public static let cake = "com.phillipmaizza.nextexplorer.tip.cake"
    public static let generous = "com.phillipmaizza.nextexplorer.tip.generous"
    public static let all = [coffee, cake, generous]

    /// A face for each tier, kept on the client side so a copy edit in App Store Connect can
    /// never drop the emoji from the row.
    static func emoji(for id: String) -> String {
        switch id {
        case coffee: "☕️"
        case cake: "🍰"
        default: "❤️"
        }
    }
}

/// A tip tier resolved from StoreKit, price already localized by the store.
public struct TipProduct: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    public var emoji: String { TipProductID.emoji(for: id) }

    public init(id: String, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

public enum TipPurchaseOutcome: Equatable, Sendable {
    case success
    case userCancelled
    case pending
}

public enum TipError: Error, Equatable {
    case productNotFound
    case unverified
}

@DependencyClient
public struct StoreKitTipClient: Sendable {
    public var products: @Sendable () async throws -> [TipProduct]
    public var purchase: @Sendable (_ id: String) async throws -> TipPurchaseOutcome
}

extension StoreKitTipClient: DependencyKey {
    public static let liveValue = StoreKitTipClient(
        products: {
            let storeProducts = try await Product.products(for: TipProductID.all)
            return storeProducts
                .sorted { $0.price < $1.price }
                .map { TipProduct(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice) }
        },
        purchase: { id in
            guard let product = try await Product.products(for: [id]).first else {
                throw TipError.productNotFound
            }
            switch try await product.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else { throw TipError.unverified }
                // Consumable: nothing to unlock, so finish right away.
                await transaction.finish()
                return .success
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .pending
            }
        }
    )

    public static let testValue = StoreKitTipClient()

    public static let previewValue = StoreKitTipClient(
        products: {
            [
                TipProduct(id: TipProductID.coffee, displayName: "Coffee", displayPrice: "$0.99"),
                TipProduct(id: TipProductID.cake, displayName: "Cake", displayPrice: "$2.99"),
                TipProduct(id: TipProductID.generous, displayName: "Generous", displayPrice: "$4.99"),
            ]
        },
        purchase: { _ in .success }
    )
}

extension DependencyValues {
    public var storeKitTipClient: StoreKitTipClient {
        get { self[StoreKitTipClient.self] }
        set { self[StoreKitTipClient.self] = newValue }
    }
}
