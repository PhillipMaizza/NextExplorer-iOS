import CoreModels
@testable import FilesFeature
import Localization
import Testing

struct VersionedFileWordsTests {
    @Test
    func noStateReadsAsAnyState() {
        #expect(VersionedFileWords.state(nil) == L10n.VersionedFiles.anyState)
        #expect(VersionedFileWords.state(.orphaned) == L10n.VersionedFiles.stateOrphaned)
    }

    @Test
    func aMissingZoneReadsAsUnknown() {
        #expect(VersionedFileWords.zone(nil) == L10n.VersionedFiles.zoneUnknown)
    }

    @Test
    func aVersionWithNothingToAddHasNoSubtitle() {
        #expect(VersionedFileWords.subtitle(VersionedFilesFeatureTests.version("v1")) == nil)
    }
}
