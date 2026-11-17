import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// What select mode and the `+` menu offer on a screen.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSelectionGateTests {
    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestPath.docsLowercase, size: 1)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)

    @Test("A saved copy shown with no network offers select mode only when something in it is kept")
    func selectModeNeedsAKeptItemOffline() {
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [photo, notes])
        #expect(state.canSelectItems)
        state.dataSource = .cached(fetchedAt: MockDate.date)
        #expect(!state.canSelectItems)
        state.offlineItemIDs = [photo.id]
        #expect(state.canSelectItems)
    }

    @Test("The selection menu is off when nothing in it applies to the picked items")
    func theMenuNeedsAnAction() {
        #expect(!SelectionActionsMenu.Availability(single: photo, canGetInfo: false).hasActions)
        #expect(SelectionActionsMenu.Availability(single: photo).hasActions)
        #expect(!SelectionActionsMenu.Availability(canGetInfo: true).hasActions)
        #expect(SelectionActionsMenu.Availability(canGetInfo: false, canKeepOffline: true).hasActions)
    }

    @Test("A kept screen offers nothing to add even before its access lands, a live one does")
    func addingWaitsForAccessOnlyOnLiveScreens() {
        var state = BrowseFixtures.state(TestPath.docsLowercase)
        #expect(state.canAddHere)
        state.isKeptOffline = true
        #expect(!state.canAddHere)
        #expect(!state.canUploadHere)
    }
}
