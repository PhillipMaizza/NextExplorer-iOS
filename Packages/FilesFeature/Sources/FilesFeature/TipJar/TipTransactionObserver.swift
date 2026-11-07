import Foundation
import StoreKit

/// App lifetime observer that finishes tip transactions delivered outside the inline
/// `purchase()` call. Ask to Buy approvals, and purchases interrupted then completed on a later
/// launch, arrive only through `Transaction.updates`. Left undrained, StoreKit redelivers the
/// same transaction on every launch. Tips are consumables that unlock nothing, so every tip
/// transaction is finished, an unverified one after being logged.
///
/// Start it once, as early as possible, from the app's root view `.task` so a transaction that
/// resolves while the app is backgrounded is settled the moment it returns.
public enum TipTransactionObserver {
    public static func run() async {
        for await update in Transaction.updates {
            switch update {
            case let .verified(transaction):
                await TipTransactionSettler.settleIfTip(transaction, verificationError: nil)
            case let .unverified(transaction, error):
                await TipTransactionSettler.settleIfTip(transaction, verificationError: error)
            }
        }
    }
}
