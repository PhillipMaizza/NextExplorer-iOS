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
    @Test("The user volumes flag comes from the server features and paints from the next launch's first frame")
    func userVolumesFlagIsReadAndRemembered() async {
        let cache = JSONCacheStore.inMemory()
        let store = TestStore(initialState: withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            BrowseFixtures.state()
        }) {
            BrowseFeature()
        } withDependencies: {
            $0.jsonCacheStore = cache
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isUserVolumesEnabled: true))) {
            $0.isUserVolumesEnabled = true
        }
        await store.finish()

        let next = withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            BrowseFixtures.state()
        }
        #expect(next.isUserVolumesEnabled)
    }

    @Test("A member with user volumes on is told none are assigned; everyone else that the server has none")
    func rootGuideFollowsRoleAndFlag() {
        var state = BrowseFixtures.state()
        #expect(state.rootEmptyGuide == .browseRootNoVolumes)

        state.isUserVolumesEnabled = true
        #expect(state.rootEmptyGuide == .browseRootUnassigned)

        state.isAdmin = true
        #expect(state.rootEmptyGuide == .browseRootNoVolumes)

        #expect(BrowseFixtures.state(TestFolder.files, title: TestFolder.files).rootEmptyGuide == nil)
    }

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

    @Test("The Browse tab hands the account's admin role to its root")
    func browseTabPassesTheRoleToTheRoot() {
        let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        #expect(BrowseTabFeature.State(serverURL: serverURL, isAdmin: true).root.isAdmin)
        #expect(!BrowseTabFeature.State(serverURL: serverURL).root.isAdmin)
    }
}
