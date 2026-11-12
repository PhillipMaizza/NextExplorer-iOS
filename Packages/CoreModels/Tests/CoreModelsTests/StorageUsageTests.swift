@testable import CoreModels
import Foundation
import Testing

@Suite("StorageUsage")
struct StorageUsageTests {
    private func decode(_ fixture: CoreModelsFixture) throws -> StorageUsage {
        try fixture.decode(StorageUsage.self)
    }

    @Test("decodes a full usage response")
    func decodesFull() throws {
        let usage = try decode(.storageUsageFortyOfHundred)
        #expect(usage.used == 40)
        #expect(usage.capacity == 100)
        #expect(abs(usage.fraction - 0.4) < 0.0001)
        #expect(usage.isMeaningful)
    }

    @Test("used is filled disk (capacity - free), not the target folder's own size")
    func usedIsFilledDisk() throws {
        // A small folder (`size` 5) on a nearly full volume: filled disk is 90, not 5.
        let usage = try decode(.storageUsageSmallFolderOnNearlyFullDisk)
        #expect(usage.used == 90)
        #expect(abs(usage.fraction - 0.9) < 0.0001)
    }

    @Test("capacity falls back to used + free when df reported no total")
    func capacityFallback() throws {
        let usage = try decode(.storageUsageNoTotalReported)
        #expect(usage.capacity == 100)
        #expect(abs(usage.fraction - 0.3) < 0.0001)
    }

    @Test("an all-zero (denied) response is not meaningful and fraction is 0")
    func deniedResponse() throws {
        let usage = try decode(.storageUsageDeniedAllZero)
        #expect(!usage.isMeaningful)
        #expect(usage.fraction == 0)
    }

    @Test("fraction clamps to 1 when used exceeds capacity")
    func fractionClamps() throws {
        let usage = try decode(.storageUsageUsedExceedsCapacity)
        #expect(usage.fraction == 1)
    }

    @Test("missing keys default to zero")
    func missingKeys() throws {
        let usage = try decode(.emptyObject)
        #expect(usage.path.isEmpty)
        #expect(usage.capacity == 0)
    }
}

@Suite("ServerFeatures volume usage")
struct ServerFeaturesVolumeUsageTests {
    @Test("decodes volumeUsage.enabled")
    func decodesFlag() throws {
        let features = try CoreModelsFixture.serverFeaturesVolumeUsageEnabledUserVolumesDisabled.decode(ServerFeatures.self)
        #expect(features.isVolumeUsageEnabled)
        #expect(!features.isUserVolumesEnabled)
    }

    @Test("defaults to false when the section is absent")
    func defaultsFalse() throws {
        let features = try CoreModelsFixture.emptyObject.decode(ServerFeatures.self)
        #expect(!features.isVolumeUsageEnabled)
    }
}

@Suite("ServerFeatures personal folders")
struct ServerFeaturesPersonalTests {
    @Test("decodes personal.enabled")
    func decodesFlag() throws {
        let features = try CoreModelsFixture.serverFeaturesPersonalEnabled.decode(ServerFeatures.self)
        #expect(features.isPersonalEnabled)
    }

    @Test("defaults to false when the section is absent")
    func defaultsFalse() throws {
        let features = try CoreModelsFixture.emptyObject.decode(ServerFeatures.self)
        #expect(!features.isPersonalEnabled)
    }
}
