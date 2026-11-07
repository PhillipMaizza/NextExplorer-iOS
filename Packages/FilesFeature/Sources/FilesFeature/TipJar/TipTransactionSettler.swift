import Foundation
import os
import StoreKit

/// The slice of a StoreKit transaction the tip flow needs, so settling can be tested with a fake
/// (a real `Transaction` cannot be constructed outside StoreKit).
protocol TipSettleable: Sendable {
    var productID: String { get }
    func finish() async
}

extension Transaction: TipSettleable {}

/// Finishes tip transactions, verified or not. A tip is a consumable that unlocks nothing, so a
/// transaction that failed JWS verification grants nothing either way; it is logged and then
/// finished so StoreKit stops redelivering it on every launch.
enum TipTransactionSettler {
    private enum Constants {
        static let subsystem = "com.phillipmaizza.nextexplorer"
        static let category = "TipJar"
    }

    private static let logger = Logger(subsystem: Constants.subsystem, category: Constants.category)

    /// Returns whether the transaction was verified.
    @discardableResult
    static func settle(_ result: VerificationResult<Transaction>) async -> Bool {
        switch result {
        case let .verified(transaction):
            await settle(transaction, verificationError: nil)
        case let .unverified(transaction, error):
            await settle(transaction, verificationError: error)
        }
    }

    @discardableResult
    static func settle(_ transaction: some TipSettleable, verificationError: (any Error)?) async -> Bool {
        if let verificationError {
            logger.error(
                "Finishing unverified tip transaction for \(transaction.productID, privacy: .public): \(String(describing: verificationError), privacy: .public)"
            )
        }
        await transaction.finish()
        return verificationError == nil
    }

    /// Settles only transactions for the tip products; anything else is left for its owner.
    static func settleIfTip(_ transaction: some TipSettleable, verificationError: (any Error)?) async {
        guard TipProductID.all.contains(transaction.productID) else { return }
        await settle(transaction, verificationError: verificationError)
    }
}
