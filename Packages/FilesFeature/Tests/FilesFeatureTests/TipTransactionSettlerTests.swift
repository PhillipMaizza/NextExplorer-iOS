import ComposableArchitecture
@testable import FilesFeature
import Foundation
import Testing

struct TipTransactionSettlerTests {
    private struct VerificationFailure: Error {}

    private final class FakeTransaction: TipSettleable {
        let productID: String
        private let finishCount = LockIsolated(0)

        init(productID: String) {
            self.productID = productID
        }

        var finishes: Int {
            finishCount.value
        }

        func finish() async {
            finishCount.withValue { $0 += 1 }
        }
    }

    @Test
    func aVerifiedTipTransactionIsFinishedAndReportedVerified() async {
        let transaction = FakeTransaction(productID: TipProductID.coffee)

        let isVerified = await TipTransactionSettler.settle(transaction, verificationError: nil)

        #expect(isVerified)
        #expect(transaction.finishes == 1)
    }

    @Test
    func anUnverifiedTipTransactionIsStillFinishedSoItIsNotRedelivered() async {
        let transaction = FakeTransaction(productID: TipProductID.cake)

        let isVerified = await TipTransactionSettler.settle(transaction, verificationError: VerificationFailure())

        #expect(!isVerified)
        #expect(transaction.finishes == 1)
    }

    @Test(arguments: TipProductID.all)
    func theObserverFinishesVerifiedAndUnverifiedUpdatesForEveryTipProduct(productID: String) async {
        let verified = FakeTransaction(productID: productID)
        let unverified = FakeTransaction(productID: productID)

        await TipTransactionSettler.settleIfTip(verified, verificationError: nil)
        await TipTransactionSettler.settleIfTip(unverified, verificationError: VerificationFailure())

        #expect(verified.finishes == 1)
        #expect(unverified.finishes == 1)
    }

    @Test
    func theObserverLeavesTransactionsForOtherProductsAlone() async {
        let other = FakeTransaction(productID: "com.example.other")

        await TipTransactionSettler.settleIfTip(other, verificationError: nil)
        await TipTransactionSettler.settleIfTip(other, verificationError: VerificationFailure())

        #expect(other.finishes == 0)
    }
}
