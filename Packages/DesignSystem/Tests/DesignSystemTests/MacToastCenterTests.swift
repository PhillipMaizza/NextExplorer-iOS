#if os(macOS)
    @testable import DesignSystem
    import Foundation
    import Testing
    import TestUtils

    @MainActor
    @Suite("MacToastCenter")
    struct MacToastCenterTests {
        private let center = MacToastCenter(dismissDelay: .seconds(3600))

        @Test("a new message stacks on top and its host draws the stack")
        func newMessageStacks() {
            let first = TestID.uuid()
            let second = TestID.uuid()
            let copied = DSToastMessage.success("Copied")
            let moved = DSToastMessage.success("Moved")
            center.update(from: nil, to: copied, owner: first, surface: .host(first)) { _ in }
            center.update(from: nil, to: moved, owner: second, surface: .host(second)) { _ in }
            #expect(center.entries.map(\.id) == [copied.id, moved.id])
            #expect(center.renderer == .host(second))
        }

        @Test("a message replaced by its host stays until it times out, a replaced progress swaps in place")
        func replacing() {
            let owner = TestID.uuid()
            let copied = DSToastMessage.success("Copied")
            let moved = DSToastMessage.success("Moved")
            center.update(from: nil, to: copied, owner: owner, surface: .host(owner)) { _ in }
            center.update(from: copied, to: moved, owner: owner, surface: .host(owner)) { _ in }
            #expect(center.entries.map(\.id) == [copied.id, moved.id])

            let progressOwner = TestID.uuid()
            let one = DSToastMessage.progress("Copying 1")
            let two = DSToastMessage.progress("Copying 2")
            center.update(from: nil, to: one, owner: progressOwner, surface: .host(progressOwner)) { _ in }
            center.update(from: one, to: two, owner: progressOwner, surface: .host(progressOwner)) { _ in }
            #expect(center.entries.map(\.id) == [copied.id, moved.id, two.id])
        }

        @Test("closing a message clears its host only while the host still shows it")
        func closingClearsHost() {
            let owner = TestID.uuid()
            let copied = DSToastMessage.success("Copied")
            var cleared: [String] = []
            center.update(from: nil, to: copied, owner: owner, surface: .host(owner)) { cleared.append($0) }
            center.dismiss(copied.id)
            #expect(center.entries.isEmpty)
            #expect(cleared == [copied.id])
        }

        @Test("the action runs once and the message goes")
        func actionRuns() {
            var runs = 0
            let undo = DSToastMessage.success("Moved", actionTitle: "Undo") { runs += 1 }
            center.update(from: nil, to: undo, owner: TestID.uuid(), surface: .pane) { _ in }
            center.run(undo.id)
            center.run(undo.id)
            #expect(runs == 1)
            #expect(center.entries.isEmpty)
        }

        @Test("a host that goes away takes its messages and hands the stack to the next host")
        func hostGone() {
            let first = TestID.uuid()
            let second = TestID.uuid()
            let copied = DSToastMessage.success("Copied")
            center.update(from: nil, to: copied, owner: first, surface: .host(first)) { _ in }
            center.update(from: nil, to: .success("Moved"), owner: second, surface: .host(second)) { _ in }
            center.hostGone(second)
            #expect(center.entries.map(\.id) == [copied.id])
            #expect(center.renderer == .host(first))
        }

        @Test("hosts in the main window share the stack drawn on the pane")
        func paneHostsShareTheStack() {
            let browse = TestID.uuid()
            let uploads = TestID.uuid()
            center.update(from: nil, to: .success("Moved"), owner: browse, surface: .pane) { _ in }
            center.update(from: nil, to: .success("Uploaded"), owner: uploads, surface: .pane) { _ in }
            center.hostGone(uploads)
            #expect(center.entries.count == 1)
            #expect(center.renderer == .pane)
        }

        @Test("the stack keeps at most five messages, dropping the oldest finished one")
        func trimsOldest() {
            let owner = TestID.uuid()
            let progress = DSToastMessage.progress("Compressing")
            center.update(from: nil, to: progress, owner: owner, surface: .host(owner)) { _ in }
            for index in 1 ... MacToastCenter.maxKept {
                center.update(from: nil, to: .success("Done \(index)"), owner: TestID.uuid(), surface: .pane) { _ in }
            }
            #expect(center.entries.count == MacToastCenter.maxKept)
            #expect(center.entries.first?.id == progress.id)
        }
    }
#endif
