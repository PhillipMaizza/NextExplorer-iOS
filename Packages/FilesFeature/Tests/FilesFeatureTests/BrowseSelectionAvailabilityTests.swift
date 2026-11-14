import CoreModels
@testable import FilesFeature
import Testing
import TestUtils

/// What the selection menu offers: everything on a live listing, and on a screen listing the device
/// only what works on kept files, once every pick is kept.
@MainActor
struct BrowseSelectionAvailabilityTests {
    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestFolder.docs)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestFolder.docs)

    private func state(isKeptOffline: Bool, kept: Set<String>) -> BrowseFeature.State {
        let access = BrowseFeature.shownAccess(BrowseTestSupport.fullAccess, isNarrowed: isKeptOffline)
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [photo, notes], access: access)
        state.isKeptOffline = isKeptOffline
        state.isSelecting = true
        state.selectedItemIDs = [photo.id, notes.id]
        state.offlineItemIDs = kept
        return state
    }

    @Test("A live listing offers info, sharing, copying, moving, deleting, saving and keeping offline")
    func aLiveListingOffersEverything() {
        let availability = state(isKeptOffline: false, kept: []).selectionAvailability

        #expect(availability.canGetInfo)
        #expect(availability.canShare)
        #expect(!availability.sharesKeptFiles)
        #expect(availability.canTransfer)
        #expect(availability.canMove)
        #expect(availability.canDelete)
        #expect(availability.canSave)
        #expect(availability.canKeepOffline)
        #expect(availability.offlineAction == .add)
    }

    @Test("Kept files on a device screen offer only sharing the copies, saving them and the removal")
    func keptFilesOfferOnlyOfflineActions() {
        let availability = state(isKeptOffline: true, kept: [photo.id, notes.id]).selectionAvailability

        #expect(!availability.canGetInfo)
        #expect(!availability.canShare)
        #expect(availability.sharesKeptFiles == BrowseFeature.State.canShareKeptFiles)
        #expect(!availability.canTransfer)
        #expect(!availability.canMove)
        #expect(!availability.canDelete)
        #expect(!availability.canFavorite)
        #expect(availability.canSave)
        #expect(availability.canKeepOffline)
        #expect(availability.offlineAction == .remove)
    }

    @Test("A device screen pick that is not kept yet offers nothing to save, share or remove")
    func aPickNotKeptYetOffersNothing() {
        let availability = state(isKeptOffline: true, kept: [photo.id]).selectionAvailability

        #expect(!availability.sharesKeptFiles)
        #expect(!availability.canSave)
        #expect(!availability.canKeepOffline)
    }

    @Test("A lone pick is the single item; two are not")
    func theSingleItemIsTheLonePick() {
        var state = state(isKeptOffline: false, kept: [])
        #expect(state.singleSelectedItem == nil)

        state.selectedItemIDs = [notes.id]
        #expect(state.singleSelectedItem == notes)
        #expect(state.selectedItems == [notes])
    }
}
