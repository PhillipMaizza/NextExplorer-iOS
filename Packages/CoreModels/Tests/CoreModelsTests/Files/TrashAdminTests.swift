@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct TrashAdminTests {
    private func encoded(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Settings

    @Test
    func systemSettingsCarryTrashAndVersions() throws {
        let settings = try CoreModelsFixture.trashAdminSystemSettingsTrashAndVersions.decode(SystemSettings.self)

        #expect(settings.trash == TrashSettings(
            isEnabled: false,
            retentionDays: 14,
            maxPercent: 25,
            maxBytes: 5 * TrashSettings.bytesPerGiB
        ))
        #expect(settings.versions == VersionsSettings(
            isEnabled: true,
            keepAllHours: 12,
            hourlyDays: 3,
            dailyDays: 20,
            maxPerFile: 80,
            sessionCheckpointMinutes: 5
        ))
    }

    @Test
    func emptySectionsTakeTheServersDefaults() throws {
        #expect(try CoreModelsFixture.emptyObject.decode(TrashSettings.self) == TrashSettings())
        #expect(try CoreModelsFixture.emptyObject.decode(VersionsSettings.self) == VersionsSettings())
        #expect(TrashSettings().isEnabled)
        #expect(TrashSettings().retentionDays == 30)
        #expect(TrashSettings().maxPercent == 10)
        #expect(TrashSettings().maxBytes == nil)
    }

    @Test
    func noSizeCapIsSentAsNullToClearIt() throws {
        let json = try encoded(TrashSettings(maxBytes: nil))

        #expect(json["maxBytes"] is NSNull)
        #expect(try encoded(TrashSettings(maxBytes: 1_073_741_824))["maxBytes"] as? Int == 1_073_741_824)
    }

    // MARK: Size cap field

    @Test(arguments: [
        ("", Int?.none, true),
        (TestValue.blank, nil, true),
        ("1", TrashSettings.bytesPerGiB, true),
        ("2.5", 2_684_354_560, true),
        ("2,5", 2_684_354_560, true),
        ("0.01", 10_737_418, true),
    ])
    func theSizeCapFieldParses(text: String, bytes: Int?, isValid: Bool) {
        let parsed = TrashSettings.maxBytes(fromGiBText: text)

        #expect((parsed != nil) == isValid)
        #expect(parsed == .some(bytes))
    }

    @Test(arguments: ["0", "-1", "abc", "1.2.3", "NaN", "inf", "99999999999", "1e30", "999999999999999999999999"])
    func aBadSizeCapIsInvalid(text: String) {
        #expect(TrashSettings.maxBytes(fromGiBText: text) == nil)
    }

    @Test(arguments: [
        (0, ""),
        (5 * TrashSettings.bytesPerGiB, "5"),
        (2_684_354_560, "2.5"),
        (1_610_612_736, "1.5"),
    ])
    func theSizeCapShowsAsWholeOrTwoDecimalGiB(bytes: Int, text: String) {
        #expect(TrashSettings(maxBytes: bytes == 0 ? nil : bytes).maxSizeGiBText == text)
    }

    // MARK: Zones

    @Test
    func aZoneDecodesItsSpaceLastPassAndJournal() throws {
        let zone = try CoreModelsFixture.trashAdminZoneWithLastPassAndEvents.decode(TrashZone.self)

        #expect(zone.kind == .personal)
        #expect(zone.isAvailable)
        #expect(zone.heldBytes == 1500)
        #expect(zone.usedPercent == 15)
        #expect(zone.lastPass?.purged == 4)
        #expect(zone.events.first?.id == "7")
        #expect(zone.events.first?.kind == "version-evicted")
    }

    @Test
    func anUnavailableZoneCarriesItsReasonAndNoBudget() throws {
        let zone = try CoreModelsFixture.trashAdminZoneUnavailableWithoutBudget.decode(TrashZone.self)

        #expect(zone.kind == .userVolume)
        #expect(!zone.isAvailable)
        #expect(zone.reason == "replaced")
        #expect(zone.budgetBytes == nil)
        #expect(zone.usedPercent == 0)
    }

    @Test
    func anUnknownZoneKindIsAPlainVolume() throws {
        #expect(try CoreModelsFixture.trashAdminZoneUnknownKind.decode(TrashZone.self).kind == .volume)
    }

    @Test(arguments: [(0, 1000, 0), (500, 1000, 50), (1000, 1000, 100), (5000, 1000, 100), (1, 1000, 0)])
    func theUsedShareIsCappedAtAHundred(held: Int, budget: Int, percent: Int) {
        #expect(TrashZone(id: "z", name: "x", usedBytes: held, budgetBytes: budget).usedPercent == percent)
    }

    @Test
    func aZeroBudgetIsNoShare() {
        #expect(TrashZone(id: "z", name: "x", usedBytes: 100, budgetBytes: 0).usedPercent == 0)
    }

    // MARK: Verification

    @Test
    func verificationCountsViolationsWhateverTheirShape() throws {
        let result = try CoreModelsFixture.trashAdminVerificationMixedViolationShapes.decode(TrashVerification.self)

        #expect(result.zoneID == "z1")
        #expect(result.violationCount == 3)
        #expect(try CoreModelsFixture.trashAdminVerificationEmptyViolations.decode(TrashVerification.self)
            .violationCount == 0)
        #expect(try CoreModelsFixture.trashAdminVerificationMissingViolations.decode(TrashVerification.self)
            .violationCount == 0)
    }

    // MARK: Patch

    @Test
    func aTrashAndVersionsPatchCarriesOnlyThoseSections() throws {
        let json = try encoded(SystemSettingsPatch(
            trash: TrashSettings(retentionDays: 7),
            versions: VersionsSettings(maxPerFile: 10)
        ))

        #expect(Set(json.keys) == ["trash", "versions"])
        let trash = try #require(json["trash"] as? [String: Any])
        #expect(trash["retentionDays"] as? Int == 7)
        let versions = try #require(json["versions"] as? [String: Any])
        #expect(versions["maxPerFile"] as? Int == 10)
    }
}

extension TrashAdminTests {
    @Test(arguments: [(0, 1000, 0.0), (500, 1000, 0.5), (1000, 1000, 1.0), (5000, 1000, 1.0)])
    func theUsedFractionIsCappedAtOne(held: Int, budget: Int, fraction: Double) {
        #expect(TrashZone(id: "z", name: "x", usedBytes: held, budgetBytes: budget).usedFraction == fraction)
    }

    @Test
    func noBudgetMeansNoFraction() {
        #expect(TrashZone(id: "z", name: "x", usedBytes: 100).usedFraction == 0)
        #expect(TrashZone(id: "z", name: "x", usedBytes: 100, budgetBytes: 0).usedFraction == 0)
    }

    @Test
    func verificationKeepsEachViolationsInvariantAndDetail() throws {
        let result = try CoreModelsFixture.trashAdminVerificationWithInvariantAndDetail.decode(TrashVerification.self)

        #expect(result.violations == [.init(invariant: "I1", detail: "content missing")])
        #expect(result.violationCount == 1)
    }
}
