import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseRootEmptyTests {
    @Test("A root that only lists My Files is not empty")
    func myFilesRowKeepsTheRootFromBeingEmpty() {
        var state = BrowseFixtures.state()
        #expect(state.hasNothingToList)

        state.isPersonalSpaceEnabled = true
        #expect(!state.hasNothingToList)

        state.isPersonalSpaceEnabled = false
        state.items = [BrowseFixtures.folder(TestFolder.files)]
        #expect(!state.hasNothingToList)
    }
}
