import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// The actions a row swipes to and a grid tile offers VoiceOver: one list for both.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseQuickActionTests {
    private let photos = BrowseFixtures.folder(TestFolder.photos, in: TestPath.docsLowercase)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)

    private func titles(_ item: FileItem, _ state: BrowseFeature.State) -> [String] {
        let store = Store(initialState: state) { EmptyReducer<BrowseFeature.State, BrowseFeature.Action>() }
        return BrowseQuickAction.actions(for: item, store: store).map(\.title)
    }

    @Test("A writable folder offers delete, favorite and rename on a folder")
    func aWritableFolder() {
        let state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [photos, notes])

        #expect(titles(photos, state) == [
            L10n.Common.delete,
            L10n.Browse.actionAddToFavorites,
            L10n.Browse.actionRename,
        ])
        #expect(titles(notes, state) == [L10n.Common.delete, L10n.Browse.actionRename])
    }

    @Test("A read only folder offers only the favorite")
    func aReadOnlyFolder() {
        let state = BrowseFixtures.loadedState(
            TestPath.docsLowercase,
            items: [photos],
            access: BrowseTestSupport.readOnlyAccess
        )

        #expect(titles(photos, state) == [L10n.Browse.actionAddToFavorites])
    }

    @Test("Select mode offers nothing, a tap picks instead")
    func selectMode() {
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [notes])
        state.isSelecting = true

        #expect(titles(notes, state).isEmpty)
    }

    @Test("A kept item on device content can only be taken off the device")
    func keptDeviceContent() {
        var state = BrowseFixtures.loadedState(
            TestPath.docsLowercase,
            items: [notes],
            access: BrowseTestSupport.readOnlyAccess
        )
        state.isKeptOffline = true
        state.offlineItemIDs = [notes.id]

        #expect(titles(notes, state) == [L10n.Browse.actionRemoveFromOffline])
    }
}
