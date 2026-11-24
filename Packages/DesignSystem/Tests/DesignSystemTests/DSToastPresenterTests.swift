@testable import DesignSystem
import Foundation
import Testing
import TestUtils

@MainActor
@Suite("DSToastPresenter")
struct DSToastPresenterTests {
    @Test("the first toast shows at once")
    func firstShowsImmediately() {
        let presenter = DSToastPresenter()
        let toast = DSToastMessage.success("Copied")
        presenter.set(toast, owner: TestID.uuid())
        #expect(presenter.visibleID == toast.id)
    }

    @Test("setting the toast already on screen again changes nothing a view could observe")
    func repeatedSetPublishesNothing() {
        let presenter = DSToastPresenter()
        let owner = TestID.uuid()
        let toast = DSToastMessage.success("Copied")
        let changed = ChangeFlag()
        withObservationTracking {
            presenter.set(toast, owner: owner)
        } onChange: {
            changed.value = true
        }
        withObservationTracking {
            presenter.set(toast, owner: owner)
            presenter.set(nil, owner: TestID.uuid())
        } onChange: {
            changed.value = true
        }
        presenter.set(toast, owner: owner)
        #expect(!changed.value)
    }

    @Test("a new toast waits for the current one to leave")
    func newToastWaitsForCurrent() async {
        let presenter = DSToastPresenter()
        let owner = TestID.uuid()
        let first = DSToastMessage.success("Copied")
        let second = DSToastMessage.success("Ready to move")
        presenter.set(first, owner: owner)
        presenter.set(second, owner: owner)
        #expect(presenter.visibleID == nil)
        await presenter.swapTask?.value
        #expect(presenter.visibleID == second.id)
    }

    @Test("toasts from different screens never show together")
    func differentOwnersSwap() async {
        let presenter = DSToastPresenter()
        let first = DSToastMessage.success("Sync completed")
        let second = DSToastMessage.failure("Could not copy")
        presenter.set(first, owner: TestID.uuid())
        presenter.set(second, owner: TestID.uuid())
        #expect(presenter.visibleID == nil)
        await presenter.swapTask?.value
        #expect(presenter.visibleID == second.id)
    }

    @Test("a toast still set underneath returns once the newer one clears")
    func pendingToastReturns() async {
        let presenter = DSToastPresenter()
        let progressOwner = TestID.uuid()
        let otherOwner = TestID.uuid()
        let progress = DSToastMessage.progress("Extracting…")
        let success = DSToastMessage.success("Copied")
        presenter.set(progress, owner: progressOwner)
        presenter.set(success, owner: otherOwner)
        await presenter.swapTask?.value
        #expect(presenter.visibleID == success.id)
        presenter.set(nil, owner: otherOwner)
        #expect(presenter.visibleID == nil)
        await presenter.swapTask?.value
        #expect(presenter.visibleID == progress.id)
    }

    @Test("a progress toast rebuilt from the same text stays on screen without a swap")
    func rebuiltProgressStaysVisible() {
        let presenter = DSToastPresenter()
        let owner = TestID.uuid()
        presenter.set(.progress("Moving…"), owner: owner)
        presenter.set(.progress("Moving…"), owner: owner)
        #expect(presenter.visibleID == DSToastMessage.progress("Moving…").id)
        #expect(presenter.swapTask == nil)
    }

    @Test("a progress toast with new text swaps in")
    func progressWithNewTextSwaps() async {
        let presenter = DSToastPresenter()
        let owner = TestID.uuid()
        presenter.set(.progress("Moving…"), owner: owner)
        presenter.set(.progress("Copying…"), owner: owner)
        #expect(presenter.visibleID == nil)
        await presenter.swapTask?.value
        #expect(presenter.visibleID == DSToastMessage.progress("Copying…").id)
    }

    @Test("brief toasts with the same text stay distinct, so each gets its own timer")
    func briefToastsWithSameTextDiffer() {
        #expect(DSToastMessage.success("Copied") != DSToastMessage.success("Copied"))
        #expect(DSToastMessage.failure("Could not copy") != DSToastMessage.failure("Could not copy"))
    }

    @Test("clearing the only toast hides it")
    func clearingHides() {
        let presenter = DSToastPresenter()
        let owner = TestID.uuid()
        presenter.set(.success("Copied"), owner: owner)
        presenter.set(nil, owner: owner)
        #expect(presenter.visibleID == nil)
    }
}

private final class ChangeFlag: @unchecked Sendable {
    var value = false
}
