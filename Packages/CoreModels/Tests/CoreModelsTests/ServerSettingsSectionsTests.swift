@testable import CoreModels
import Foundation
import Testing

struct ServerSettingsSectionsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func encoded(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: SystemSettings

    @Test
    func systemSettingsDecodesTheFourBackgroundSections() throws {
        let settings = try decode(SystemSettings.self, """
        {
            "uploads": { "chunkedEnabled": true, "chunkedAutoFallback": false, "chunkSizeBytes": 16777216 },
            "ffmpeg": { "ffmpegPath": "/usr/bin/ffmpeg", "ffprobePath": null },
            "searchIndex": { "enabled": true, "excludedPaths": ["Backups"], "environmentExcludedPaths": ["tmp"] },
            "folderSize": { "mode": "shallow", "excludedPaths": ["docker"], "environmentExcludedPaths": [] }
        }
        """)

        #expect(settings.uploads == UploadSettings(isChunkedEnabled: true, isChunkedAutoFallback: false, chunkSizeBytes: 16 * 1024 * 1024))
        #expect(settings.ffmpeg == FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: ""))
        #expect(settings.searchIndex == SearchIndexSettings(isEnabled: true, excluded: ExcludedPaths(paths: ["Backups"], environmentPaths: ["tmp"])))
        #expect(settings.folderSize == FolderSizeSettings(mode: .shallow, excluded: ExcludedPaths(paths: ["docker"])))
    }

    @Test
    func aNonAdminResponseHasNoBackgroundSections() throws {
        let settings = try decode(SystemSettings.self, #"{ "user": { "showHiddenFiles": true } }"#)

        #expect(settings.uploads == nil)
        #expect(settings.ffmpeg == nil)
        #expect(settings.searchIndex == nil)
        #expect(settings.folderSize == nil)
    }

    @Test
    func anUnknownFolderSizeModeFallsBackToOff() throws {
        let folderSize = try decode(FolderSizeSettings.self, #"{ "mode": "everything" }"#)

        #expect(folderSize.mode == .off)
    }

    @Test
    func emptySectionsTakeTheirDefaults() throws {
        #expect(try decode(UploadSettings.self, "{}") == UploadSettings())
        #expect(try decode(FFmpegSettings.self, "{}") == FFmpegSettings())
        #expect(try decode(SearchIndexSettings.self, "{}") == SearchIndexSettings())
        #expect(try decode(FolderSizeSettings.self, "{}") == FolderSizeSettings())
    }

    // MARK: Chunk size

    @Test(arguments: [
        (0, 8, 8),
        (-5, 8, 8),
        (1_048_576, 512, 1),
        (16 * 1_048_576, 512, 16),
        (600 * 1_048_576, 512, 512),
        (100 * 1_048_576, 32, 32),
        (1_500_000, 512, 1),
        (0, 4, 4),
    ])
    func chunkSizeStaysWithinOneAndTheCeiling(bytes: Int, ceiling: Int, expected: Int) {
        #expect(UploadSettings(chunkSizeBytes: bytes).chunkSizeMiB(maxMiB: ceiling) == expected)
    }

    // MARK: FFmpeg

    @Test(arguments: [
        ("", "", true),
        ("/usr/bin/ffmpeg", "", true),
        ("", "/usr/bin/ffprobe", true),
        ("/a", "/b", true),
        ("ffmpeg", "", false),
        ("", "bin/ffprobe", false),
        ("/a", "relative", false),
    ])
    func onlyAbsoluteOrEmptyPathsAreValid(ffmpeg: String, ffprobe: String, isValid: Bool) {
        #expect(FFmpegSettings(ffmpegPath: ffmpeg, ffprobePath: ffprobe).isValid == isValid)
    }

    @Test
    func anEmptyFFmpegPathIsSentAsNullToClearTheOverride() throws {
        let json = try encoded(FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: ""))

        #expect(json["ffmpegPath"] as? String == "/usr/bin/ffmpeg")
        #expect(json["ffprobePath"] is NSNull)
    }

    // MARK: Excluded paths

    @Test
    func addingAPathDropsLeadingSlashesAndKeepsTheListSorted() {
        let excluded = ExcludedPaths(paths: ["Zeta", "alpha"])

        #expect(excluded.adding("/Backups/2024") == ["alpha", "Backups/2024", "Zeta"])
        #expect(excluded.adding("///Mid") == ["alpha", "Mid", "Zeta"])
    }

    @Test(arguments: ["", "   ", "/", "///", "alpha", "/alpha", "  alpha  ", "tmp"])
    func addingABlankDuplicateOrEnvironmentPathChangesNothing(raw: String) {
        let excluded = ExcludedPaths(paths: ["alpha"], environmentPaths: ["tmp"])

        #expect(excluded.adding(raw) == ["alpha"])
    }

    // MARK: Patch

    @Test
    func aPatchEncodesOnlyTheSectionsThatAreSet() throws {
        let json = try encoded(SystemSettingsPatch(searchIndex: .init(enabled: true)))

        #expect(Set(json.keys) == ["searchIndex"])
        let searchIndex = try #require(json["searchIndex"] as? [String: Any])
        #expect(searchIndex["enabled"] as? Bool == true)
        #expect(searchIndex["excludedPaths"] == nil)
    }

    @Test
    func aFolderSizePatchCarriesTheModeOrThePathsNotBoth() throws {
        let mode = try encoded(SystemSettingsPatch(folderSize: .init(mode: .full)))
        let paths = try encoded(SystemSettingsPatch(folderSize: .init(excludedPaths: ["a", "b"])))

        let modeBody = try #require(mode["folderSize"] as? [String: Any])
        #expect(modeBody["mode"] as? String == "full")
        #expect(modeBody["excludedPaths"] == nil)
        let pathsBody = try #require(paths["folderSize"] as? [String: Any])
        #expect(pathsBody["excludedPaths"] as? [String] == ["a", "b"])
        #expect(pathsBody["mode"] == nil)
    }

    @Test
    func anUploadsPatchSendsAllThreeFields() throws {
        let json = try encoded(SystemSettingsPatch(uploads: UploadSettings(isChunkedEnabled: true, isChunkedAutoFallback: false, chunkSizeBytes: 8_388_608)))

        let uploads = try #require(json["uploads"] as? [String: Any])
        #expect(uploads["chunkedEnabled"] as? Bool == true)
        #expect(uploads["chunkedAutoFallback"] as? Bool == false)
        #expect(uploads["chunkSizeBytes"] as? Int == 8_388_608)
    }

    // MARK: ServerFeatures

    @Test
    func serverFeaturesReadTheCeilingAndTheLocks() throws {
        let features = try decode(ServerFeatures.self, """
        {
            "uploads": { "maxChunkSizeBytes": 67108864 },
            "search": { "index": { "enabled": true, "lockedBy": "SEARCH_INDEX" } },
            "folderSize": { "mode": "full", "enabled": true, "lockedBy": "FOLDER_SIZE_MODE" }
        }
        """)

        #expect(features.maxUploadChunkSizeBytes == 67_108_864)
        #expect(features.isSearchIndexEnabled)
        #expect(features.searchIndexLockedBy == "SEARCH_INDEX")
        #expect(features.folderSizeMode == .full)
        #expect(features.folderSizeLockedBy == "FOLDER_SIZE_MODE")
    }

    @Test
    func serverFeaturesWithoutThoseSectionsAreUnlockedAndOff() throws {
        let features = try decode(ServerFeatures.self, "{}")

        #expect(features.maxUploadChunkSizeBytes == nil)
        #expect(!features.isSearchIndexEnabled)
        #expect(features.searchIndexLockedBy == nil)
        #expect(features.folderSizeMode == .off)
        #expect(features.folderSizeLockedBy == nil)
    }

    @Test
    func anFFmpegPatchSendsOnlyThePathsSetAndClearsWithNull() throws {
        func json(_ patch: SystemSettingsPatch.FFmpegPatch) throws -> [String: Any] {
            let data = try JSONEncoder().encode(patch)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        #expect(try json(.init(ffmpegPath: "/a")).keys.sorted() == ["ffmpegPath"])
        #expect(try json(.init(ffprobePath: "")).keys.sorted() == ["ffprobePath"])
        #expect(try json(.init(ffprobePath: ""))["ffprobePath"] is NSNull)
        #expect(try json(.init()).isEmpty)
    }
}
