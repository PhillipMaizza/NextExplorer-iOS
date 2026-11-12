import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

private let receiver = BrowseDropFixtures.receiver

private func entry(_ name: String, in path: String = TestFolder.docs) -> FileItem {
    BrowseDropFixtures.entry(name, in: path)
}

/// What a drag carries out of a listing and how that payload decodes on the receiving side.
@Suite(.isolatedDependencies)
struct BrowseDragPayloadTests {
    @Test("A reference survives an encode and decode round trip with its batch and identity")
    func referenceSurvivesAnEncodeDecodeRoundTrip() throws {
        let report = entry(TestFile.report)
        let reference = ServerItemReference(dragging: report, selection: [report, entry("b.pdf")], origin: receiver)

        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: JSONEncoder().encode(reference))

        #expect(decoded.id == report.id)
        #expect(decoded.items.map(\.id) == ["Docs/report.pdf", "Docs/b.pdf"])
        #expect(decoded.origin == receiver)
    }

    @Test("A payload from before batches and identities still decodes, with neither")
    func aPayloadWrittenBeforeBatchesAndIdentitiesStillDecodes() throws {
        // The payload of an older build: an object that carries only the id.
        let json = try FilesFeatureFixture.legacyDragReference.data()

        let decoded = try JSONDecoder().decode(ServerItemReference.self, from: json)

        #expect(decoded.id == "Docs/a.pdf")
        #expect(decoded.items.isEmpty)
        #expect(decoded.origin == nil)
    }

    @Test("Dragging a row outside the selection carries only that row")
    func draggingARowOutsideTheSelectionCarriesOnlyThatRow() {
        let outside = entry("outside.pdf")
        let reference = ServerItemReference(dragging: outside, selection: [entry(TestFile.aPDF), entry("b.pdf")])

        #expect(reference.items == [outside])
    }

    @Test("Dragging the only selected row carries only that row")
    func draggingTheOnlySelectedRowCarriesOnlyThatRow() {
        let only = entry(TestFile.aPDF)

        #expect(ServerItemReference(dragging: only, selection: [only]).items == [only])
        #expect(ServerItemReference(dragging: only).items == [only])
    }

    @Test("A batch lists each row once")
    func aBatchListsEachRowOnce() {
        let a = entry(TestFile.aPDF)
        let reference = ServerItemReference(id: a.id, item: a, batch: [a, a, entry("b.pdf")])

        #expect(reference.items.map(\.name) == [TestFile.aPDF, "b.pdf"])
    }

    @Test("The drag payload is not built until the drag starts")
    func theDragPayloadIsNotBuiltUntilTheDragStarts() {
        let calls = LockIsolated(0)
        let builder = DraggedServerItemBuilder(
            item: entry(TestFile.aPDF), serverURL: BrowseTestSupport.serverURL, scope: receiver.scope, filesClient: .previewValue,
            selection: {
                calls.withValue { $0 += 1 }
                return []
            }
        )
        #expect(calls.value == 0)

        let payload = builder.build()

        #expect(calls.value == 1)
        #expect(payload.reference.origin == receiver)
    }
}
