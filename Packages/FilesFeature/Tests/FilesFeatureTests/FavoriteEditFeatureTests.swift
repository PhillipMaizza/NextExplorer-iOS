import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct FavoriteEditFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private nonisolated func favorite(
        label: String? = "Docs", icon: String = "outline:StarIcon", color: String? = nil
    ) -> Favorite {
        Favorite(
            id: "f1", path: "Documents", label: label, icon: icon, color: color,
            position: 0, createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date()
        )
    }

    @Test
    func seedsDraftsFromTheFavoriteAndStartsClean() {
        let state = FavoriteEditFeature.State(
            serverURL: serverURL,
            favorite: favorite(icon: "solid:BriefcaseIcon", color: "#009cff")
        )
        #expect(state.nameDraft == "Docs")
        #expect(state.nameError == nil)
        #expect(state.iconDraft == "BriefcaseIcon")
        #expect(state.iconStyleDraft == .solid)
        #expect(state.colorDraft == "#009cff")
        #expect(state.iconToken == "solid:BriefcaseIcon")
        #expect(state.isDirty == false)
    }

    @Test
    func fieldChangesFlipDirtyAndClearErrors() async {
        var initial = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite())
        initial.errorMessage = "stale"
        let store = TestStore(initialState: initial) { FavoriteEditFeature() }

        await store.send(.nameChanged("Projects")) {
            $0.nameDraft = "Projects"
            $0.errorMessage = nil
        }
        #expect(store.state.isDirty)

        await store.send(.iconSelected("BriefcaseIcon")) { $0.iconDraft = "BriefcaseIcon" }
        await store.send(.iconStyleSelected(.solid)) { $0.iconStyleDraft = .solid }
        await store.send(.colorSelected("#0bd336")) { $0.colorDraft = "#0bd336" }
    }

    @Test
    func togglingOnlyTheIconWeightIsADirtyChange() async {
        let store = TestStore(
            initialState: FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite(icon: "outline:StarIcon"))
        ) { FavoriteEditFeature() }

        await store.send(.iconStyleSelected(.solid)) { $0.iconStyleDraft = .solid }
        #expect(store.state.isDirty)
        #expect(store.state.iconToken == "solid:StarIcon")
    }

    @Test
    func saveSendsTheDraftsAndForwardsTheUpdate() async {
        var initial = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite())
        initial.nameDraft = "Projects"
        initial.iconDraft = "BriefcaseIcon"
        initial.colorDraft = "#0bd336"

        let updated = Favorite(
            id: "f1", path: "Documents", label: "Projects", icon: "BriefcaseIcon", color: "#0bd336",
            position: 0, createdAt: initial.favorite.createdAt, updatedAt: Date()
        )
        let store = TestStore(initialState: initial) {
            FavoriteEditFeature()
        } withDependencies: {
            $0.filesClient.updateFavorite = { _, id, label, icon, color in
                #expect(id == "f1")
                #expect(label == "Projects")
                #expect(icon == "outline:BriefcaseIcon")
                #expect(color == "#0bd336")
                return updated
            }
        }

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) { $0.isSaving = false }
        await store.receive(\.delegate)
    }

    @Test
    func anEmptyNameFlagsAnErrorAndBlocksSaving() async {
        var initial = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite())
        initial.iconDraft = "BriefcaseIcon" // dirty, so only the name gates the save
        let store = TestStore(initialState: initial) { FavoriteEditFeature() }

        await store.send(.nameChanged("   ")) { $0.nameDraft = "   " }
        #expect(store.state.nameError == .empty)
        #expect(store.state.isSaveEnabled == false)

        await store.send(.saveTapped) // guarded — no effect
    }

    @Test
    func aSaveFailureSurfacesAMessage() async {
        var initial = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite())
        initial.nameDraft = "Projects"
        let store = TestStore(initialState: initial) {
            FavoriteEditFeature()
        } withDependencies: {
            $0.filesClient.updateFavorite = { _, _, _, _, _ in throw FilesClientError.server(statusCode: 404) }
        }

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = FilesClientError.server(statusCode: 404).userMessage
        }
    }
}
