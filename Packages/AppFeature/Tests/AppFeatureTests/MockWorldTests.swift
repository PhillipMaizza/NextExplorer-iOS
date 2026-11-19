@testable import AppFeature
import CoreModels
import FilesClient
import Foundation
import Testing
import TestUtils

/// The UI tests' mocked server beyond the file tree: the seeded trash, the admin's people,
/// volumes, activity, versions and access rules, and the per area empty and failure switches.
struct MockWorldTests {
    private typealias Entry = UITestFixture.TrashEntry
    private typealias Person = UITestFixture.ManagedUser

    private enum Constants {
        static let missingID = "missing"
        /// A name no area has, after the separator.
        static let unknownArea = ",unknown"
    }

    private let serverURL = UITestSupport.serverURL

    private func seededTree() -> MockFileTree {
        MockFileTree(
            seed: MockBrowseTree.seed(now: MockDate.date),
            trash: MockBrowseTree.trash(now: MockDate.date)
        )
    }

    private func trashID(_ entry: Entry, in tree: MockFileTree) throws -> String {
        try #require(tree.trashListing().items.first { $0.name == entry.name }).id
    }

    @Test
    func theSeededTrashHoldsOneItemPerRowState() throws {
        let items = seededTree().trashListing().items
        #expect(items.map(\.name).sorted() == Entry.allCases.map(\.name).sorted())
        let calendar = Calendar(identifier: .gregorian)
        let budget = try #require(items.first { $0.name == Entry.oldBudget.name })
        #expect(budget.daysUntilRemoval(now: MockDate.date, calendar: calendar) == 0)
        #expect(items.contains { !$0.isAvailable })
        #expect(items.contains { $0.shareCount > 0 && !$0.deletedBy.isYou })
        #expect(items.contains { $0.deletedBy.label == TrashItem.DeletedBy.shareLinkLabel })
    }

    @Test
    func aDeletedFolderListsWhatItHeldAndReadsItsText() throws {
        let tree = seededTree()
        let id = try trashID(.oldPhotos, in: tree)
        let listing = try #require(tree.trashEntries(id, path: ""))
        #expect(listing.entries.map(\.name) == UITestFixture.TrashedPhotosEntry.allCases.map(\.name))

        let shotList = UITestFixture.TrashedPhotosEntry.shotList.name
        #expect(tree.trashText(id, path: shotList)?.content == UITestFixture.TrashedPhotosEntry.shotListText)
        #expect(tree.trashText(id, path: UITestFixture.TrashedPhotosEntry.first.name) == nil)
        #expect(tree.trashEntries(Constants.missingID, path: "") == nil)
    }

    @Test
    func restoringASeededFolderBringsBackWhatItHeld() throws {
        let tree = seededTree()
        let id = try trashID(.oldPhotos, in: tree)
        _ = tree.restore([id])

        let photos = UITestFixture.Folder.photos.path
        #expect(tree.list(photos).contains { $0.name == Entry.oldPhotos.name })
        let restored = tree.list("\(photos)/\(Entry.oldPhotos.name)").map(\.name)
        #expect(restored == UITestFixture.TrashedPhotosEntry.allCases.map(\.name))
        #expect(tree.trashEntries(id, path: "") == nil)
    }

    @Test
    func anEntryRestoredFromADeletedFolderGetsItsFolderBackAroundIt() throws {
        let tree = seededTree()
        let id = try trashID(.oldPhotos, in: tree)
        let shotList = UITestFixture.TrashedPhotosEntry.shotList.name

        let result = tree.restoreEntries(id, paths: [shotList, Constants.missingID])

        #expect(result.items.map(\.status) == [.restored, .notFound])
        let folder = "\(UITestFixture.Folder.photos.path)/\(Entry.oldPhotos.name)"
        #expect(tree.list(UITestFixture.Folder.photos.path).contains { $0.name == Entry.oldPhotos.name })
        #expect(tree.list(folder).map(\.name) == [shotList])
        #expect(tree.trashEntries(id, path: "")?.entries.map(\.name) == [
            UITestFixture.TrashedPhotosEntry.first.name,
            UITestFixture.TrashedPhotosEntry.second.name,
        ])
    }

    @Test
    func aDeletedTextFileAtTheTopReadsItsOwnText() throws {
        let tree = seededTree()
        let id = try trashID(.dropped, in: tree)
        #expect(tree.trashText(id, path: "")?.content == Entry.droppedText)
    }

    @Test
    func peopleCanBeAddedChangedResetAndRemoved() async throws {
        let client = UITestSupport.filesClient(.normal)
        let seeded = try await client.listUsers(serverURL)
        #expect(seeded.map(\.username) == [UITestFixture.SignedInAccount.username.rawValue] + Person.allCases
            .map(\.username))
        #expect(seeded.contains { $0.isLocked })
        #expect(seeded.contains { $0.twoFactorEnabled && $0.isAdmin })

        let newUser = UITestFixture.NewUser.casey
        let added = try await client.createUser(serverURL, CreateUserRequest(
            email: newUser.email,
            password: UITestFixture.Credential.password.rawValue,
            isAdmin: false
        ))
        #expect(added.username == newUser.rawValue)

        _ = try await client.updateUser(serverURL, Person.sam.id, UpdateUserRequest(roles: [UserRole.admin]))
        try await client.resetUserSecurity(serverURL, Person.riley.id, .lock)
        try await client.deleteUser(serverURL, Person.jamie.id)

        let after = try await client.listUsers(serverURL)
        #expect(after.contains { $0.id == added.id })
        #expect(after.first { $0.id == Person.sam.id }?.isAdmin == true)
        #expect(after.first { $0.id == Person.riley.id }?.isLocked == false)
        #expect(!after.contains { $0.id == Person.jamie.id })
        await #expect(throws: FilesClientError.self) {
            try await client.setUserPassword(serverURL, Person.jamie.id, UITestFixture.Credential.password.rawValue)
        }
    }

    @Test
    func aPersonsVolumesStartSeededAndKeepEachChange() async throws {
        let client = UITestSupport.filesClient(.normal)
        let userID = Person.jamie.id
        let seeded = try await client.userVolumes(serverURL, userID)
        #expect(seeded.map(\.label) == UITestFixture.ManagedVolume.allCases.map(\.rawValue))

        let archive = try #require(seeded.first { $0.label == UITestFixture.ManagedVolume.archive.rawValue })
        _ = try await client.updateUserVolume(serverURL, userID, archive.id, nil, .readwrite)
        try await client.removeUserVolume(serverURL, userID, seeded[0].id)

        let after = try await client.userVolumes(serverURL, userID)
        #expect(after.map(\.id) == [archive.id])
        #expect(after.first?.accessMode == .readwrite)
    }

    @Test
    func theActivityLogFiltersAndClears() async throws {
        let client = UITestSupport.filesClient(.normal)
        let all = try await client.fetchActivity(serverURL, ActivityFilter(), nil)
        #expect(all.events.count == UITestFixture.ActivityAction.allCases.count * ActivityOutcome.allCases.count)

        let refused = try await client.fetchActivity(serverURL, ActivityFilter(outcome: .refused), nil)
        #expect(refused.events.allSatisfy { $0.outcome == .refused })
        let byPerson = try await client.fetchActivity(serverURL, ActivityFilter(query: Person.sam.username), nil)
        #expect(!byPerson.events.isEmpty)
        #expect(byPerson.events.allSatisfy { $0.actor == Person.sam.username })

        try await client.clearActivity(serverURL)
        #expect(try await client.fetchActivity(serverURL, ActivityFilter(), nil).events.isEmpty)
    }

    @Test
    func deletingVersionsShrinksAFileAndDeletingAllDropsIt() async throws {
        let client = UITestSupport.filesClient(.normal)
        let notes = "\(UITestFixture.VersionedFile.notes)"
        let detail = try await client.fetchVersionedFile(serverURL, notes)
        #expect(detail.versions.count == UITestFixture.VersionedFile.notes.versionCount)
        #expect(detail.versions.first?.isPinned == true)

        let one = try await client.deleteVersionsOfFile(serverURL, notes, [detail.versions[1].id])
        #expect(one.deleted == 1)
        #expect(one.remaining == detail.versions.count - 1)

        _ = try await client.deleteVersionsOfFile(serverURL, notes, nil)
        let page = try await client.fetchVersionedFiles(
            serverURL,
            VersionedFilesFilter(),
            0,
            VersionedFilesPage.defaultPageSize
        )
        #expect(!page.files.contains { $0.id == notes })
        #expect(page.files.count == UITestFixture.VersionedFile.allCases.count - 1)
    }

    @Test
    func accessRulesKeepWhatWasSaved() async throws {
        let client = UITestSupport.filesClient(.normal)
        let seeded = try await client.fetchSystemSettings(serverURL).accessRules
        #expect(try await client.fetchSystemSettings(serverURL).activity?.isEnabled == true)
        #expect(seeded.map(\.path) == UITestFixture.AccessRulePath.allCases.map(\.rawValue))

        _ = try await client.updateAccessRules(serverURL, Array(seeded.prefix(1)))
        #expect(try await client.fetchSystemSettings(serverURL).accessRules == Array(seeded.prefix(1)))
    }

    @Test
    func anEmptyAreaListsNothingAndAFailingOneThrows() async throws {
        var client = UITestSupport.filesClient(.normal)
        UITestSupport.empty([.trash, .users], in: &client)
        #expect(try await client.fetchTrash(serverURL).items.isEmpty)
        #expect(try await client.listUsers(serverURL).map(\.id) == [UITestSupport.user.id])

        UITestSupport.fail(Set(UITestArea.allCases), in: &client)
        await #expect(throws: FilesClientError.self) { try await client.favorites(serverURL) }
        await #expect(throws: FilesClientError.self) { try await client.fetchActivity(serverURL, ActivityFilter(), nil)
        }
        await #expect(throws: FilesClientError.self) { try await client.fetchSystemSettings(serverURL) }
    }

    @Test
    func anAreaListSurvivesTheLaunchEnvironment() {
        let areas: Set<UITestArea> = [.trash, .accessRules, .users]
        #expect(UITestArea.parse(UITestArea.launchValue(areas)) == areas)
        #expect(UITestArea.parse(nil).isEmpty)
        #expect(UITestArea.parse(UITestArea.launchValue([.trash]) + Constants.unknownArea) == [.trash])
    }
}
