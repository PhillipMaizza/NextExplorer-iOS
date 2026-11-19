import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SharedFeatureItemsTests {
    private let serverURL = TestHost.serverURL
    private let day: TimeInterval = 86_400
    private let anna = User(id: "u1", username: "anna", email: nil, displayName: "Anna Moreau")
    private let jonas = User(id: "u2", username: "jonas", email: nil, displayName: "Jonas Keller")
    private let lea = User(id: "u3", username: "lea", email: nil, displayName: "Lea Sato")

    /// A By me link on `path`, created `age` seconds after the mock date so the default
    /// newest first sort puts higher ages first.
    private func byMe(
        _ id: String,
        path: String,
        space: String? = nil,
        users: [String]? = nil,
        expiresAt: Date? = nil,
        downloads: Int = 0,
        openedAt: Date? = nil,
        age: TimeInterval = 0
    ) -> Share {
        Share(
            id: id,
            shareToken: "tok\(id)",
            ownerId: "me",
            sourcePath: path,
            sourceSpace: space,
            isDirectory: false,
            accessMode: .readonly,
            sharingType: users == nil ? .anyone : .users,
            hasPassword: false,
            expiresAt: expiresAt,
            downloadCount: downloads,
            lastAccessedAt: openedAt,
            permittedUserIds: users,
            createdAt: MockDate.date.addingTimeInterval(age),
            updatedAt: MockDate.date
        )
    }

    private func withMe(_ id: String, owner: String, name: String, age: TimeInterval = 0) -> Share {
        Share(
            id: id,
            shareToken: "tok\(id)",
            ownerId: owner,
            sourceName: name,
            isDirectory: false,
            accessMode: .readonly,
            sharingType: .users,
            hasPassword: false,
            createdAt: MockDate.date.addingTimeInterval(age),
            updatedAt: MockDate.date
        )
    }

    private func state(byMe: [Share] = [], withMe: [Share] = []) -> SharedFeature.State {
        var state = SharedFeature.State(serverURL: serverURL)
        state.now = MockDate.date
        state.byMe = IdentifiedArray(uniqueElements: byMe)
        state.withMe = IdentifiedArray(uniqueElements: withMe)
        state.userNames = Dictionary(uniqueKeysWithValues: [anna, jonas, lea].map { (
            $0.id,
            $0.displayName ?? $0.username
        ) })
        return state
    }

    // MARK: Grouping

    @Test
    func sharesOfOnePathBecomeOneItemWithFullyExpiredItemsLast() {
        let link = byMe("a", path: "/Work/Roadmap/", age: 30)
        let people = byMe("b", path: "Work/Roadmap", users: ["u1"], age: 20)
        let lapsed = byMe("c", path: "Old/invoice.pdf", expiresAt: MockDate.date, age: 40)
        let solo = byMe("d", path: "Keynote.key", users: ["u2"], age: 10)

        let items = state(byMe: [link, people, lapsed, solo]).items(for: .byMe)

        #expect(items.map(\.name) == ["Roadmap", "Keynote.key", "invoice.pdf"])
        #expect(items[0].shares.map(\.id) == ["b", "a"])
        #expect(items[0].location == "Work")
        #expect(items[1].location == nil)
        #expect(items[2].isExpired)
        #expect(items[2].badges.first?.expiry == .expired)
    }

    @Test
    func theSamePathInAnotherSpaceStaysItsOwnItem() {
        let personal = byMe("a", path: "Notes.md", space: "personal")
        let volume = byMe("b", path: "Notes.md", space: "volume")

        #expect(state(byMe: [personal, volume]).items(for: .byMe).count == 2)
    }

    @Test
    func withMeKeepsEveryShareApartAndNamesTheSharer() {
        let first = withMe("w1", owner: "u1", name: "Report.pdf", age: 10)
        let second = withMe("w2", owner: "u9", name: "Report.pdf")

        let items = state(withMe: [first, second]).items(for: .withMe)

        #expect(items.map(\.id) == ["w1", "w2"])
        #expect(items[0].badges[0].people == [SharedFeature.Person(id: "u1", name: "Anna Moreau")])
        #expect(items[1].badges[0].people[0].name == state().sharedByLabel(for: second))
        #expect(items.allSatisfy { $0.location == nil })
    }

    @Test
    func unresolvedRecipientsCountAsUnnamed() {
        let share = byMe("a", path: "Plan.md", users: ["u1", "u99"])

        let badge = state(byMe: [share]).items(for: .byMe)[0].badges[0]

        #expect(badge.people.map(\.id) == ["u1"])
        #expect(badge.unnamedCount == 1)
        #expect(!badge.isAnyone)
    }

    // MARK: Filter row

    @Test
    func filterOptionsCountItemsPerPersonMostSharedFirst() {
        let shares = [
            byMe("a", path: "Roadmap", age: 40),
            byMe("b", path: "Roadmap", users: ["u2", "u1"], age: 30),
            byMe("c", path: "Budget.xlsx", users: ["u2"], age: 20),
            byMe("d", path: "Logo.png", users: ["u3", "u99"], age: 10),
        ]

        let options = state(byMe: shares).filterOptions(for: .byMe)

        #expect(options.map(\.filter) == [.all, .anyone, .people(["u2"]), .people(["u1"]), .people(["u3"])])
        #expect(options.map(\.count) == [3, 1, 2, 1, 1])
    }

    @Test
    func withMeOffersSharersButNoAnyone() {
        let shares = [withMe("w1", owner: "u1", name: "A"), withMe("w2", owner: "u2", name: "B")]

        let options = state(withMe: shares).filterOptions(for: .withMe)

        #expect(options.map(\.filter) == [.all, .people(["u1"]), .people(["u2"])])
    }

    @Test
    func theFilterRowHidesWhenItCouldNarrowNothing() {
        let onePerson = state(byMe: [byMe("a", path: "A", users: ["u1"])])
        let twoPeople = state(byMe: [byMe("a", path: "A", users: ["u1"]), byMe("b", path: "B", users: ["u2"])])
        var filtered = onePerson
        filtered.filters[.byMe] = .people(["u1"])

        #expect(!onePerson.isFilterRowVisible(for: .byMe))
        #expect(twoPeople.isFilterRowVisible(for: .byMe))
        #expect(filtered.isFilterRowVisible(for: .byMe))
    }

    @Test
    func choosingAFilterNarrowsTheListAndAllClearsIt() async {
        let shares = [
            byMe("a", path: "Roadmap", age: 30),
            byMe("b", path: "Roadmap", users: ["u1"], age: 20),
            byMe("c", path: "Budget.xlsx", users: ["u2"], age: 10),
        ]
        let store = TestStore(initialState: state(byMe: shares)) {
            SharedFeature()
        }

        await store.send(.filterChanged(.byMe, .people(["u2"]))) { $0.filters[.byMe] = .people(["u2"]) }
        #expect(store.state.items(for: .byMe).map(\.name) == ["Budget.xlsx"])
        #expect(store.state.items(for: .withMe).isEmpty)

        await store.send(.filterChanged(.byMe, .anyone)) { $0.filters[.byMe] = .anyone }
        // The item keeps only its link share under Anyone.
        #expect(store.state.items(for: .byMe).map(\.shares.count) == [1])

        await store.send(.filterChanged(.byMe, .all)) { $0.filters[.byMe] = nil }
        #expect(store.state.items(for: .byMe).count == 2)
    }

    @Test
    func peopleWithASharedItemJoinThePickAndOthersStartANewOne() async {
        let shares = [
            byMe("a", path: "Roadmap", users: ["u1", "u2"], age: 30),
            byMe("b", path: "Budget.xlsx", users: ["u1"], age: 20),
            byMe("c", path: "Notes.md", users: ["u3"], age: 10),
        ]
        let store = TestStore(initialState: state(byMe: shares)) {
            SharedFeature()
        }

        await store.send(.filterChanged(.byMe, .people(["u1"]))) { $0.filters[.byMe] = .people(["u1"]) }
        let dimmed = store.state.filterOptions(for: .byMe).filter(\.isDimmed).compactMap(\.filter.personID)
        #expect(dimmed == ["u3"])

        await store.send(.filterChanged(.byMe, .people(["u2"]))) { $0.filters[.byMe] = .people(["u1", "u2"]) }
        #expect(store.state.items(for: .byMe).map(\.name) == ["Roadmap"])

        await store.send(.filterChanged(.byMe, .people(["u1"]))) { $0.filters[.byMe] = .people(["u2"]) }
        await store.send(.filterChanged(.byMe, .people(["u3"]))) { $0.filters[.byMe] = .people(["u3"]) }
        await store.send(.filterChanged(.byMe, .people(["u3"]))) { $0.filters[.byMe] = nil }
    }

    @Test
    func withMeKeepsWhatAnyPickedSharerShared() async {
        let shares = [
            withMe("w1", owner: "u1", name: "Q3.pdf"),
            withMe("w2", owner: "u2", name: "Plan.md"),
            withMe("w3", owner: "u3", name: "Notes.md"),
        ]
        let store = TestStore(initialState: state(withMe: shares)) {
            SharedFeature()
        }

        await store.send(.filterChanged(.withMe, .people(["u1"]))) { $0.filters[.withMe] = .people(["u1"]) }
        await store.send(.filterChanged(.withMe, .people(["u2"]))) { $0.filters[.withMe] = .people(["u1", "u2"]) }
        #expect(Set(store.state.items(for: .withMe).map(\.name)) == ["Q3.pdf", "Plan.md"])
        #expect(!store.state.filterOptions(for: .withMe).contains { $0.isDimmed })
    }

    @Test
    func aPickWithNoCommonShareLeftResets() async {
        var initial = state(byMe: [byMe("a", path: "A", users: ["u1", "u2"]), byMe("b", path: "B", users: ["u1"])])
        initial.filters[.byMe] = .people(["u1", "u2"])
        let store = TestStore(initialState: initial) {
            SharedFeature()
        }

        await store.send(.deleteResponse("a", .success(true))) {
            $0.byMe.remove(id: "a")
            $0.filters[.byMe] = nil
        }
    }

    @Test
    func deletingThePersonsLastShareResetsTheirFilter() async {
        var initial = state(byMe: [byMe("a", path: "A", users: ["u1"]), byMe("b", path: "B", users: ["u2"])])
        initial.filters[.byMe] = .people(["u1"])
        let store = TestStore(initialState: initial) {
            SharedFeature()
        }

        await store.send(.deleteResponse("a", .success(true))) {
            $0.byMe.remove(id: "a")
            $0.filters[.byMe] = nil
        }
    }

    @Test
    func aPersonLeavingTheUserListResetsTheirFilter() async {
        var initial = state(byMe: [byMe("a", path: "A", users: ["u1"]), byMe("b", path: "B", users: ["u2"])])
        initial.filters[.byMe] = .people(["u1"])
        let store = TestStore(initialState: initial) {
            SharedFeature()
        }

        await store.send(.usersResponse([jonas])) {
            $0.userNames = ["u2": "Jonas Keller"]
            $0.filters[.byMe] = nil
        }
    }

    // MARK: Expiry

    @Test
    func theCountdownRoundsUpAndOnlyShowsInTheLastWeek() {
        let current = state()
        let notice = { (offset: TimeInterval) in
            current.expiryNotice(for: byMe("a", path: "A", expiresAt: MockDate.date.addingTimeInterval(offset)))
        }

        #expect(notice(0) == .expired)
        #expect(notice(-day) == .expired)
        #expect(notice(day / 2) == .daysLeft(1))
        #expect(notice(day * 2.5) == .daysLeft(3))
        #expect(notice(day * 7) == .daysLeft(7))
        #expect(notice(day * 7 + 1) == nil)
        #expect(current.expiryNotice(for: byMe("a", path: "A")) == nil)
    }

    @Test
    func theTickAdvancesOnlyWhenACountdownDayTurnsOver() async {
        let expiresAt = MockDate.date.addingTimeInterval(day * 2.5)
        let store = TestStore(initialState: state(byMe: [byMe("a", path: "A", expiresAt: expiresAt)])) {
            SharedFeature()
        }

        // Inside the same countdown day nothing changes.
        await store.send(.expiryTick(MockDate.date.addingTimeInterval(day / 4)))
        // Crossing two days before expiry turns 3 days left into 2.
        let nextDay = MockDate.date.addingTimeInterval(day / 2 + 1)
        await store.send(.expiryTick(nextDay)) { $0.now = nextDay }
        #expect(store.state.expiryNotice(for: store.state.byMe[0]) == .daysLeft(2))
        // Crossing the expiry itself moves the item into Expired.
        let lapsed = expiresAt.addingTimeInterval(1)
        await store.send(.expiryTick(lapsed)) { $0.now = lapsed }
        #expect(store.state.items(for: .byMe)[0].isExpired)
    }

    @Test
    func theNearestExpiryIsTheSoonestLiveShareOrTheLastToEnd() {
        let current = state()
        let item = { (shares: [Share], isExpired: Bool) in
            SharedFeature.Item(id: "A", name: "A", location: nil, shares: shares, badges: [], isExpired: isExpired)
        }
        let soon = byMe("soon", path: "A", expiresAt: MockDate.date.addingTimeInterval(day))
        let later = byMe("later", path: "A", expiresAt: MockDate.date.addingTimeInterval(day * 9))
        let never = byMe("never", path: "A")
        let lapsed = byMe("lapsed", path: "A", expiresAt: MockDate.date.addingTimeInterval(-day))
        let older = byMe("older", path: "A", expiresAt: MockDate.date.addingTimeInterval(-day * 3))

        #expect(current.nearestExpiringShare(in: item([later, soon, never, lapsed], false))?.id == "soon")
        #expect(current.nearestExpiringShare(in: item([never, lapsed], false)) == nil)
        #expect(current.nearestExpiringShare(in: item([older, lapsed], true))?.id == "lapsed")
    }

    @Test
    func anItemSumsDownloadsAndKeepsTheLatestOpen() {
        let current = state(byMe: [
            byMe("a", path: "A", downloads: 3, openedAt: MockDate.date.addingTimeInterval(-day)),
            byMe("b", path: "A", downloads: 24, openedAt: MockDate.date.addingTimeInterval(-60), age: 1),
            byMe("c", path: "A", age: 2),
        ])
        let item = current.items(for: .byMe)[0]

        #expect(item.downloadCount == 27)
        #expect(item.lastOpenedAt == MockDate.date.addingTimeInterval(-60))
        #expect(state(byMe: [byMe("d", path: "D")]).items(for: .byMe)[0].lastOpenedAt == nil)
    }

    @Test
    func aSearchThatTheFilterEmptiesCountsAsNoResults() {
        var current = state(byMe: [
            byMe("a", path: "Roadmap", users: ["u1"]),
            byMe("b", path: "Budget", users: ["u2"], age: 1),
        ])
        current.searchQuery = "Budget"
        #expect(!current.isSearchWithoutResults(for: .byMe))

        current.filters[.byMe] = .people(["u1"])
        #expect(current.isSearchWithoutResults(for: .byMe))
    }

    @Test
    func theFactsNameTheExpiryAndExplainAnExpiredLink() {
        let share = byMe("a", path: "A", expiresAt: MockDate.date.addingTimeInterval(-day))
        let expired = SharedShareFacts(share: share, notice: .expired, dateFormat: .dashYearMonthDay)
        let soon = SharedShareFacts(share: share, notice: .daysLeft(2), dateFormat: .dashYearMonthDay)
        let undated = SharedShareFacts(share: byMe("b", path: "B"), notice: nil, dateFormat: .dashYearMonthDay)

        #expect(expired.isExpired)
        #expect(expired.expiresTitle == L10n.Shared.metaExpired)
        #expect(expired.expiredNote != nil)
        #expect(soon.expiresTitle == L10n.Shared.metaExpires)
        #expect(soon.expiredNote == nil)
        #expect(undated.expires == L10n.Common.never)
        #expect(undated.lastOpened == L10n.Common.never)
        #expect(undated.password == L10n.Common.off)
        guard case .warning = soon.expiresStyle, case .error = expired.expiresStyle,
              case .secondary = undated.expiresStyle
        else {
            Issue.record("Expiry colours should follow the notice")
            return
        }
    }

    @Test
    func theAudienceTitleCountsPeopleOrNamesThePublicLink() {
        #expect(byMe("a", path: "A").audienceTitle == L10n.Shared.anyoneWithLink)
        #expect(byMe("b", path: "B", users: ["u1", "u2"]).audienceTitle == L10n.Shared.peopleCount(2))
    }

    /// One item with two shares: a link opened once, and a people share downloaded more.
    private var roadmapShares: [Share] {
        [
            byMe("a", path: "Roadmap", downloads: 4, openedAt: MockDate.date),
            byMe("b", path: "Roadmap", users: ["u1", "u2"], downloads: 6, age: 1),
        ]
    }

    @Test
    func aMacRowActsOnOneShareOnlyAndListsSeveralAsChildren() {
        let current = state(byMe: roadmapShares + [byMe("c", path: "Budget", age: 2)])
        let items = current.items(for: .byMe)
        let budget = MacSharedRow(item: items[0], expiringShare: nil)
        let roadmap = MacSharedRow(item: items[1], expiringShare: nil)

        #expect(budget.share?.id == "c")
        #expect(budget.children == nil)
        #expect(roadmap.share == nil)
        #expect(roadmap.children?.map(\.id) == [
            .share("a", item: ":Roadmap"),
            .share("b", item: ":Roadmap"),
        ])
        #expect(roadmap.children?.map { $0.share?.id } == ["a", "b"])
        #expect(roadmap.children?.first?.children == nil)
        #expect(MacSharedRow.ID.share("a", item: ":Roadmap").itemID == ":Roadmap")
    }

    @Test
    func macRowsSortByTheirOwnSharesOrTheWholeItem() {
        let current = state(byMe: roadmapShares)
        let roadmap = MacSharedRow(item: current.items(for: .byMe)[0], expiringShare: nil)
        let second = roadmap.children?[1]

        #expect(roadmap.downloadCount == 10)
        #expect(roadmap.recipientCount == 2)
        #expect(roadmap.lastOpenedSortDate == MockDate.date)
        #expect(roadmap.expirySortDate == .distantFuture)
        #expect(second?.downloadCount == 6)
        #expect(second?.lastOpenedAt == nil)
        #expect(second?.lastOpenedSortDate == .distantPast)
        let byDownloads = roadmap.children?.sorted(using: KeyPathComparator(\.downloadCount, order: .reverse))
        #expect(byDownloads?.map { $0.share?.id } == ["b", "a"])
    }
}
