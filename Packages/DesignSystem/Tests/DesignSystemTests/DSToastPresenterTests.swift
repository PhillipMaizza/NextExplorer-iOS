@testable import DesignSystem
import Foundation
import Testing

@MainActor
@Suite("DSToastPresenter")
struct DSToastPresenterTests {
    private let settle: Duration = .milliseconds(500)

    @Test("the first toast shows at once")
    func firstShowsImmediately() {
        let presenter = DSToastPresenter()
        let toast = DSToastMessage.success("Copied")
        presenter.set(toast, owner: UUID())
        #expect(presenter.visibleID == toast.id)
    }

    @Test("a new toast waits for the current one to leave")
    func newToastWaitsForCurrent() async throws {
        let presenter = DSToastPresenter()
        let owner = UUID()
        let first = DSToastMessage.success("Copied")
        let second = DSToastMessage.success("Ready to move")
        presenter.set(first, owner: owner)
        presenter.set(second, owner: owner)
        #expect(presenter.visibleID == nil)
        try await Task.sleep(for: settle)
        #expect(presenter.visibleID == second.id)
    }

    @Test("toasts from different screens never show together")
    func differentOwnersSwap() async throws {
        let presenter = DSToastPresenter()
        let first = DSToastMessage.success("Sync completed")
        let second = DSToastMessage.failure("Could not copy")
        presenter.set(first, owner: UUID())
        presenter.set(second, owner: UUID())
        #expect(presenter.visibleID == nil)
        try await Task.sleep(for: settle)
        #expect(presenter.visibleID == second.id)
    }

    @Test("a toast still set underneath returns once the newer one clears")
    func pendingToastReturns() async throws {
        let presenter = DSToastPresenter()
        let progressOwner = UUID()
        let otherOwner = UUID()
        let progress = DSToastMessage.progress("Extracting…")
        let success = DSToastMessage.success("Copied")
        presenter.set(progress, owner: progressOwner)
        presenter.set(success, owner: otherOwner)
        try await Task.sleep(for: settle)
        #expect(presenter.visibleID == success.id)
        presenter.set(nil, owner: otherOwner)
        #expect(presenter.visibleID == nil)
        try await Task.sleep(for: settle)
        #expect(presenter.visibleID == progress.id)
    }

    @Test("clearing the only toast hides it")
    func clearingHides() {
        let presenter = DSToastPresenter()
        let owner = UUID()
        presenter.set(.success("Copied"), owner: owner)
        presenter.set(nil, owner: owner)
        #expect(presenter.visibleID == nil)
    }
}
