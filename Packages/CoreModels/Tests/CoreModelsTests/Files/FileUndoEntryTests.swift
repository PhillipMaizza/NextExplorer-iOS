@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileUndoEntry")
struct FileUndoEntryTests {
    private func item(_ name: String) -> FileItem {
        FileItem(name: name, path: TestFolder.docs, dateModified: MockDate.date, size: 0, kind: TestKind.text)
    }

    private func entry(_ index: Int) -> FileUndoEntry {
        FileUndoEntry(.renamed(item("new\(index).txt"), previousName: "old\(index).txt"))
    }

    @Test("a stack exactly at the limit keeps every entry")
    func limitIsInclusive() {
        var stack: [FileUndoEntry] = []
        for index in 0 ..< FileUndoEntry.limit {
            stack.record(entry(index))
        }
        #expect(stack.count == Constants.limit)
        #expect(stack.first == entry(0))
        #expect(stack.last == entry(19))
    }

    @Test("one entry past the limit drops only the oldest")
    func overflowDropsOldest() {
        var stack: [FileUndoEntry] = []
        for index in 0 ... FileUndoEntry.limit {
            stack.record(entry(index))
        }
        #expect(stack.count == Constants.limit)
        #expect(stack.first == entry(1))
        #expect(stack.last == entry(20))
    }

    @Test("a long run keeps the 20 most recent entries in order")
    func longRunKeepsMostRecent() {
        var stack: [FileUndoEntry] = []
        for index in 0 ..< 50 {
            stack.record(entry(index))
        }
        #expect(stack == (30 ..< 50).map(entry))
    }

    @Test("a stack already over the limit is trimmed on the next record")
    func oversizedStackIsTrimmed() {
        var stack = (0 ..< 25).map(entry)
        stack.record(entry(25))
        #expect(stack == (6 ... 25).map(entry))
    }
}

private enum Constants {
    static let limit = 20
}
