import Foundation
import StoreKit

/// App lifetime observer that finishes tip transactions delivered outside the inline
/// `purchase()` call. Ask to Buy approvals, and purchases interrupted then completed on a later
/// launch, arrive only through `Transaction.updates`. Left undrained, StoreKit redelivers the
/// same transaction on every launch. Tips are consumables that unlock nothing, so verifying and
/// finishing is all that is required.
///
/// Start it once, as early as possible, from the app's root view `.task` so a transaction that
/// resolves while the app is backgrounded is settled the moment it returns.
public enum TipTransactionObserver {
    public static func run() async {
        for await update in Transaction.updates {
            guard case let .verified(transaction) = update else { continue }
            guard TipProductID.all.contains(transaction.productID) else { continue }
            await transaction.finish()
        }
    }
}
