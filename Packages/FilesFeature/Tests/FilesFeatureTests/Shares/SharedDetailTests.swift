import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// The item sheet a Shared row opens: what it shows, and how it follows deletes, edits and reloads.
@Suite(.isolatedDependencies)
@MainActor
struct SharedDetailTests {
    private enum Constants {
        static let path = "Work/Roadmap"
        static let itemID = "personal:Work/Roadmap"
        static let filePath = "Work/brochure.pdf"
        static let fileSize: Int64 = 2048
        static let noMatchQuery = "zzzznomatch"
    }

    private let serverURL = TestHost.serverURL

    /// A By me link on the roadmap folder, `age` seconds after the mock date.
    private func roadmap(
        _ id: String,
        users: [String]? = nil,
        age: TimeInterval = 0,
        filePath: String? = nil
    ) -> Share {
        Share(
            id: id,
            shareToken: "tok\(id)",
            ownerId: "me",
            sourcePath: filePath ?? Constants.path,
            sourceSpace: "personal",
            isDirectory: filePath == nil,
            accessMode: .readonly,
            sharingType: users == nil ? .anyone : .users,
            hasPassword: false,
            permittedUserIds: users,
            createdAt: MockDate.date.addingTimeInterval(age),
            updatedAt: MockDate.date
        )
    }

    private func state(
        _ shares: [Share],
        detail: SharedFeature.Detail? = SharedFeature.Detail(segment: .byMe, id: Constants.itemID)
    ) -> SharedFeature.State {
        var state = SharedFeature.State(serverURL: serverURL)
        state.now = MockDate.date
        state.byMe = IdentifiedArray(uniqueElements: shares)
        state.phases[.byMe] = .loaded
        state.detail = detail
        return state
    }

    @Test
    func openingPushingAndClosingTheSheet() async {
        let store = TestStore(initialState: state([roadmap("a"), roadmap("b", age: 1)], detail: nil)) {
            SharedFeature()
        }

        await store.send(.detailOpened(.byMe, Constants.itemID)) {
            $0.detail = SharedFeature.Detail(segment: .byMe, id: Constants.itemID)
        }
        await store.send(.detailShareSelected("b")) { $0.detail?.pushedShareID = "b" }
        await store.send(.detailShareSelected(nil)) { $0.detail?.pushedShareID = nil }
        await store.send(.detailDismissed) { $0.detail = nil }
    }

    @Test
    func theSheetListsEveryShareOnTheItemDespiteTheFilterAndSearch() {
        var state = state([roadmap("a"), roadmap("b", users: ["u1"], age: 1)])
        state.userNames = ["u1": "Anna Moreau"]
        state.filters[.byMe] = .people(["u1"])
        state.searchQuery = "zzz"

        let item = state.item(for: SharedFeature.Detail(segment: .byMe, id: Constants.itemID))

        #expect(item?.name == "Roadmap")
        #expect(item?.shares.map(\.id) == ["a", "b"])
    }

    @Test
    func aWithMeShareIsItsOwnItem() {
        var state = state([], detail: nil)
        state.withMe = [Share(
            id: "w1", shareToken: "tokw1", ownerId: "u2", sourceName: "Budget.xlsx", isDirectory: false,
            accessMode: .readwrite, sharingType: .users, hasPassword: true,
            createdAt: MockDate.date, updatedAt: MockDate.date
        )]

        let item = state.item(for: SharedFeature.Detail(segment: .withMe, id: "w1"))

        #expect(item?.name == "Budget.xlsx")
        #expect(item?.shares.map(\.id) == ["w1"])
    }

    @Test
    func deletingThePushedSharePopsToTheRoot() async {
        let kept = roadmap("a")
        let pushed = roadmap("b", age: 1)
        let initial = state(
            [kept, pushed],
            detail: SharedFeature.Detail(segment: .byMe, id: Constants.itemID, pushedShareID: "b")
        )
        let store = TestStore(initialState: initial) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.deleteShareLink = { _, _ in }
        }

        await store.send(.deleteTapped(pushed)) { $0.deleteConfirmationShare = pushed }
        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationShare = nil
            $0.deletingIDs = ["b"]
        }
        await store.receive(\.deleteResponse) {
            $0.deletingIDs = []
            $0.byMe = [kept]
            $0.detail?.pushedShareID = nil
        }
    }

    @Test
    func deletingTheOtherShareDownToOnePopsSoTheRootShowsTheOneLeft() async {
        let pushed = roadmap("a")
        let other = roadmap("b", age: 1)
        let initial = state(
            [pushed, other],
            detail: SharedFeature.Detail(segment: .byMe, id: Constants.itemID, pushedShareID: "a")
        )
        let store = TestStore(initialState: initial) { SharedFeature() }

        await store.send(.deleteResponse("b", .success(true))) {
            $0.byMe = [pushed]
            $0.detail?.pushedShareID = nil
        }
    }

    @Test
    func deletingTheLastShareClosesTheSheet() async {
        let only = roadmap("a")
        let store = TestStore(initialState: state([only])) { SharedFeature() }

        await store.send(.deleteResponse("a", .success(true))) {
            $0.byMe = []
            $0.detail = nil
        }
    }

    @Test
    func aReloadWithoutTheItemClosesTheSheet() async {
        let elsewhere = Share(
            id: "z", shareToken: "tokz", ownerId: "me", sourcePath: "Other", sourceSpace: "personal",
            isDirectory: true, accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            createdAt: MockDate.date, updatedAt: MockDate.date
        )
        let store = TestStore(initialState: state([roadmap("a")])) { SharedFeature() }

        await store.send(.sharesResponse(.byMe, .success([elsewhere]))) {
            $0.byMe = [elsewhere]
            $0.dataSources[.byMe] = .live
            $0.detail = nil
        }
    }

    @Test
    func anEditSwapsTheShareInPlaceAndKeepsThePage() async {
        let share = roadmap("a")
        let other = roadmap("b", age: 1)
        var initial = state(
            [share, other],
            detail: SharedFeature.Detail(segment: .byMe, id: Constants.itemID, pushedShareID: "a")
        )
        initial.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        let updated = Share(
            id: "a", shareToken: "toka", ownerId: "me", sourcePath: Constants.path, sourceSpace: "personal",
            isDirectory: true, accessMode: .readwrite, sharingType: .anyone, hasPassword: true,
            label: "Q1 planning", createdAt: MockDate.date, updatedAt: MockDate.date
        )
        let store = TestStore(initialState: initial) { SharedFeature() }

        await store.send(.editSheet(.presented(.delegate(.updated(updated))))) {
            $0.byMe[id: "a"] = updated
            $0.editSheet = nil
            $0.actionSuccessMessage = L10n.EditShare.saved
        }
    }

    @Test
    func closingOrLeavingTheShareDropsItsEditPage() async {
        let share = roadmap("a")
        var initial = state(
            [share, roadmap("b", age: 1)],
            detail: SharedFeature.Detail(segment: .byMe, id: Constants.itemID, pushedShareID: "a")
        )
        initial.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        let store = TestStore(initialState: initial) { SharedFeature() } withDependencies: {
            $0.date = .constant(MockDate.date)
        }

        await store.send(.detailShareSelected("a"))
        await store.send(.detailShareSelected(nil)) {
            $0.detail?.pushedShareID = nil
            $0.editSheet = nil
        }
        await store.send(.editTapped(share)) {
            $0.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        }
        await store.send(.detailDismissed) {
            $0.detail = nil
            $0.editSheet = nil
        }
    }

    @Test
    func aReloadWithoutTheEditedShareDropsItsEditPage() async {
        let share = roadmap("a")
        let other = roadmap("b", age: 1)
        var initial = state([share, other])
        initial.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        let store = TestStore(initialState: initial) { SharedFeature() }

        await store.send(.sharesResponse(.byMe, .success([other]))) {
            $0.byMe = [other]
            $0.dataSources[.byMe] = .live
            $0.editSheet = nil
        }
    }

    @Test
    func aShownToastIsClearedSoTheSameOutcomeToastsAgain() async {
        var initial = state([roadmap("a")])
        initial.actionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        initial.actionSuccessMessage = L10n.EditShare.saved
        let store = TestStore(initialState: initial) { SharedFeature() }

        await store.send(.actionToastShown) {
            $0.actionErrorMessage = nil
            $0.actionSuccessMessage = nil
        }
    }

    @Test
    func aPopoverEditOpensTheShareAndLimitStartsOnSpecificUsers() async {
        let share = roadmap("a")
        let store = TestStore(initialState: state([share])) { SharedFeature() } withDependencies: {
            $0.date = .constant(MockDate.date)
        }
        var limited = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        limited.target = .users

        await store.send(.editPopoverTapped(share, .password)) {
            $0.editPopover = .password
            $0.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        }
        await store.send(.editPopoverTapped(share, .limit)) {
            $0.editPopover = .limit
            $0.editSheet = limited
        }
        await store.send(.editPopoverDismissed) {
            $0.editPopover = nil
            $0.editSheet = nil
        }
    }

    @Test
    func aFileShareFetchesItsSizeOnceAndAFolderNever() async {
        let file = roadmap("f", filePath: Constants.filePath)
        let folder = roadmap("d")
        let fetched = LockIsolated<[String]>([])
        let store = TestStore(initialState: state([file, folder], detail: nil)) { SharedFeature() } withDependencies: {
            $0.filesClient.fetchMetadata = { _, path in
                fetched.withValue { $0.append(path) }
                return FileMetadata(
                    path: path,
                    name: "brochure.pdf",
                    kind: "pdf",
                    size: Constants.fileSize,
                    dateModified: MockDate.date,
                    dateCreated: MockDate.date
                )
            }
        }

        await store.send(.shareFileNeeded(file)) {
            $0.requestedShareFileIDs = [file.id]
        }
        await store.receive(\.shareFileResponse) {
            $0.shareFiles[file.id] = file.fileItem(size: Constants.fileSize, modified: MockDate.date)
        }
        await store.send(.shareFileNeeded(file))
        await store.send(.shareFileNeeded(folder))

        #expect(fetched.value == ["personal/\(Constants.filePath)"])
    }

    @Test
    func endingARenameWithoutAChangeLeavesWithoutSaving() async {
        let share = roadmap("a")
        let store = TestStore(initialState: state([share])) { SharedFeature() } withDependencies: {
            $0.date = .constant(MockDate.date)
        }

        await store.send(.editPopoverTapped(share, .label)) {
            $0.editPopover = .label
            $0.editSheet = EditShareFeature.State(serverURL: serverURL, share: share, now: MockDate.date)
        }
        await store.send(.labelEditEnded)
        await store.receive(\.editPopoverDismissed) {
            $0.editPopover = nil
            $0.editSheet = nil
        }
        await store.send(.labelEditEnded)
    }

    @Test
    func searchFindsALinkByThePeopleItIsSharedWith() {
        let recipient = Share.previewShareableUsers[0]
        var shared = state([roadmap("a", users: [recipient.id]), roadmap("b", filePath: Constants.filePath)])
        shared.userNames = [recipient.id: recipient.displayName ?? recipient.username]
        shared.searchQuery = String((recipient.displayName ?? recipient.username).prefix(4))

        #expect(shared.displayedShares.map(\.id) == ["a"])
    }

    @Test
    func aSearchHiddenByTheFilterPointsBackToAll() {
        let recipient = Share.previewShareableUsers[0]
        var shared = state([roadmap("a", users: [recipient.id]), roadmap("b", filePath: Constants.filePath)])
        shared.userNames = [recipient.id: recipient.displayName ?? recipient.username]
        shared.filters[.byMe] = .people([recipient.id])
        shared.searchQuery = Constants.filePath

        #expect(shared.isSearchWithoutResults(for: .byMe))
        #expect(shared.noResultsMessage(for: .byMe) == L10n.Shared.noSearchMatchesFiltered(Constants.filePath))

        shared.filters[.byMe] = nil
        shared.searchQuery = Constants.noMatchQuery
        #expect(shared.noResultsMessage(for: .byMe) == L10n.Shared.noSearchMatches(Constants.noMatchQuery))
    }
}
