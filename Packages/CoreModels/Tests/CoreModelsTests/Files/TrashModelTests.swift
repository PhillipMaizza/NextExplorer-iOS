@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Delete to trash")
struct DeleteToTrashModelTests {
    @Test("a delete impact with a trash plan reads each item's destination and the retention")
    func allToTrash() throws {
        let impact = try CoreModelsFixture.deleteImpactTrashAll.decode(DeleteImpact.self)
        let plan = try #require(impact.trash)
        #expect(plan.isEnabled)
        #expect(plan.retentionDays == 30)
        #expect(plan.trashCount == 2)
        #expect(plan.permanentCount == 0)
        #expect(plan.items.first?.shareCount == 1)
        #expect(impact.hasTrashBoundItems)
    }

    @Test("a mixed plan counts what skips the trash and lists each reason once, unknown values read as permanent")
    func mixed() throws {
        let plan = try #require(try CoreModelsFixture.deleteImpactTrashMixed.decode(DeleteImpact.self).trash)
        #expect(plan.trashCount == 1)
        #expect(plan.permanentCount == 4)
        #expect(plan.permanentReasons == [.tooLarge, .otherDevice, .unknown])
    }

    @Test("a switched off trash sends nothing to it")
    func disabled() throws {
        let impact = try CoreModelsFixture.deleteImpactTrashDisabled.decode(DeleteImpact.self)
        #expect(impact.trash?.isEnabled == false)
        #expect(impact.trash?.permanentReasons == [.disabled])
        #expect(!impact.hasTrashBoundItems)
    }

    @Test("a server older than the trash has no plan")
    func legacyImpact() throws {
        let impact = try CoreModelsFixture.deleteImpactTwoLinks.decode(DeleteImpact.self)
        #expect(impact.trash == nil)
        #expect(!impact.hasTrashBoundItems)
    }

    @Test("a delete outcome reads every status, an unknown one included, and the sizes of a refused folder")
    func outcomeStatuses() throws {
        let outcome = try CoreModelsFixture.deleteOutcomeEachStatus.decode(DeleteOutcome.self)
        #expect(outcome.items.map(\.status) == [.trashed, .deleted, .missing, .kept, .unknown])
        #expect(outcome.trashedCount == 1)
        let kept = try #require(outcome.kept.first)
        #expect(kept.reason == .tooLarge)
        #expect(kept.size == 3_435_973_837)
        #expect(kept.budgetBytes == 2_147_483_648)
    }

    @Test("the kept items pair with the request by position")
    func keptPairsByPosition() throws {
        let outcome = try CoreModelsFixture.deleteOutcomeEachStatus.decode(DeleteOutcome.self)
        let requested = ["a.txt", "b.txt", "c.txt", "big", "e.txt"].map {
            FileItem(name: $0, path: "Files", dateModified: MockDate.date, size: 0, kind: "txt")
        }
        #expect(outcome.kept(of: requested).map(\.name) == ["big"])
    }

    @Test("an older server's bare success reads as everything deleted")
    func legacyOutcome() throws {
        let outcome = try CoreModelsFixture.deleteOutcomeLegacySuccess.decode(DeleteOutcome.self)
        #expect(outcome.items.isEmpty)
        #expect(outcome.kept.isEmpty)
    }

    @Test("features carry the trash section, its error shape, and nothing on an older server")
    func features() throws {
        let enabled = try CoreModelsFixture.serverFeaturesTrashEnabled.decode(ServerFeatures.self)
        #expect(enabled.trash == TrashAvailability(isEnabled: true, retentionDays: 30))
        let failed = try CoreModelsFixture.serverFeaturesTrashErrorShape.decode(ServerFeatures.self)
        #expect(failed.trash == TrashAvailability(isEnabled: false, retentionDays: nil))
        let legacy = try CoreModelsFixture.serverFeaturesPersonalEnabled.decode(ServerFeatures.self)
        #expect(legacy.trash == nil)
    }
}

@Suite("Trash listing")
struct TrashListingTests {
    private enum Constants {
        static let daySeconds: TimeInterval = 86400
        static let hourSeconds: TimeInterval = 3600
    }

    @Test("items read their kind, dates, deleter, location, availability and share links")
    func listing() throws {
        let listing = try CoreModelsFixture.trashListing.decode(TrashListing.self)
        #expect(listing.isEnabled)
        #expect(listing.retentionDays == 30)
        #expect(listing.items.map(\.id) == ["t1", "t2", "t3"])
        let report = listing.items[0]
        #expect(!report.isDirectory)
        #expect(report.size == 2048)
        #expect(report.deletedAt != nil)
        #expect(report.deletedBy == TrashItem.DeletedBy(label: "Ada", isYou: true))
        #expect(report.location == TrashItem.Location(isPersonal: true, name: "ada", parent: "Reports"))
        #expect(report.openPath == "personal/Reports")
        #expect(report.shareCount == 2)
        let photos = listing.items[1]
        #expect(photos.isDirectory)
        #expect(!photos.isAvailable)
        #expect(photos.deletedBy.label == TrashItem.DeletedBy.shareLinkLabel)
        #expect(photos.location?.isPersonal == false)
        #expect(photos.openPath == nil)
    }

    @Test("an unreadable date or missing location stays unknown instead of failing the list")
    func lenient() throws {
        let orphan = try CoreModelsFixture.trashListing.decode(TrashListing.self).items[2]
        #expect(orphan.deletedAt == nil)
        #expect(orphan.location == nil)
        #expect(orphan.deletedBy.label == nil)
    }

    @Test("days until removal count calendar days and never go below zero")
    func daysUntilRemoval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let soon = TrashItem(
            id: "a",
            name: "a",
            expiresAt: MockDate.date.addingTimeInterval(3 * Constants.daySeconds + Constants.hourSeconds)
        )
        let past = TrashItem(id: "b", name: "b", expiresAt: MockDate.date.addingTimeInterval(-Constants.daySeconds))
        let unknown = TrashItem(id: "c", name: "c")
        #expect(soon.daysUntilRemoval(now: MockDate.date, calendar: calendar) == 3)
        #expect(past.daysUntilRemoval(now: MockDate.date, calendar: calendar) == 0)
        #expect(unknown.daysUntilRemoval(now: MockDate.date, calendar: calendar) == nil)
    }

    @Test("a deleted folder's entries read their kind and build their path inside the folder")
    func entries() throws {
        let listing = try CoreModelsFixture.trashFolderEntries.decode(TrashFolderListing.self)
        #expect(listing.path == "2026")
        #expect(listing.entries.map(\.isDirectory) == [true, false, false])
        #expect(listing.entries[0].shareCount == 1)
        #expect(listing.entries[1].size == 1024)
        #expect(listing.entries[1].path(in: listing.path) == "2026/beach.jpg")
        #expect(listing.entries[1].path(in: "") == "beach.jpg")
    }

    @Test("action results map every status, reason refinements and unknown values")
    func actionResult() throws {
        let result = try CoreModelsFixture.trashActionResultStatuses.decode(TrashActionResult.self)
        #expect(result.items.map(\.status) == [
            .restored, .restored, .destinationForbidden, .forbidden, .invalidDestination, .blocked,
            .lost, .notFound, .cancelled, .purged, .unknown,
        ])
        #expect(result.items[1].key == "2026/beach.jpg")
        #expect(result.items[0].isRenamed)
        #expect(result.items[0].restoredName == "a (1).txt")
        #expect(result.succeeded.count == 3)
        #expect(result.failed.count == 8)
        #expect(result.sharesRestored == 2)
        #expect(result.sharesDropped == 1)
    }

    @Test("an empty trash summary counts what stayed behind")
    func emptySummary() throws {
        let summary = try CoreModelsFixture.trashEmptySummary.decode(TrashEmptySummary.self)
        #expect(summary.purged == 4)
        #expect(summary.leftBehind == 3)
    }

    @Test("a restore target counts its ids or entry paths")
    func targetCount() {
        #expect(TrashTarget.items(["a", "b"]).count == 2)
        #expect(TrashTarget.entries(itemID: "a", paths: ["x"]).count == 1)
    }
}
