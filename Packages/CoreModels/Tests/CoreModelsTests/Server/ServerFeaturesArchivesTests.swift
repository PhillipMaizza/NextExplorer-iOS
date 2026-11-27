import CoreModels
import Testing

struct ServerFeaturesArchivesTests {
    @Test("ServerFeatures reads the archive formats the server can browse, lowercased")
    func decodesArchiveExtensions() throws {
        let features = try CoreModelsFixture.serverFeaturesArchives.decode(ServerFeatures.self)
        #expect(features.archiveExtensions == ["7z", "zip", "rar", "tar"])
    }

    @Test("A server older than archive browsing has no archive formats at all")
    func olderServerHasNone() throws {
        let features = try CoreModelsFixture.emptyObject.decode(ServerFeatures.self)
        #expect(features.archiveExtensions == nil)
        #expect(!features.isVersionsEnabled)
    }

    @Test("ServerFeatures reads whether the server keeps versions")
    func decodesVersionsFlag() throws {
        let features = try CoreModelsFixture.serverFeaturesVersionsEnabled.decode(ServerFeatures.self)
        #expect(features.isVersionsEnabled)
    }
}
