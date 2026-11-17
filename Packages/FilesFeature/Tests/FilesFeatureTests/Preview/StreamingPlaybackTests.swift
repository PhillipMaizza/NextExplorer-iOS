import AVFoundation
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@MainActor
struct StreamingPlaybackTests {
    private enum Constants {
        static let remoteURL = "https://files.example.com/api/preview?path=Media/clip.mp4"
        static let fileExtension = "mp4"
    }

    @Test
    func aLocalFilePlaysFromThatFileAndLetsAVFoundationManageStalls() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name()).mp4")
        let playback = StreamingPlayback(url: url, fileExtension: Constants.fileExtension)

        let asset = try #require(playback.player.currentItem?.asset as? AVURLAsset)

        #expect(asset.url == url)
        #expect(playback.player.automaticallyWaitsToMinimizeStalling)
    }

    @Test
    func aRemoteURLWithoutAnInstalledCertificateStreamsStraightFromThatURL() throws {
        let url = try #require(URL(string: Constants.remoteURL))
        let playback = StreamingPlayback(url: url, fileExtension: Constants.fileExtension)

        let asset = try #require(playback.player.currentItem?.asset as? AVURLAsset)

        #expect(asset.url == url)
        #expect(playback.player.automaticallyWaitsToMinimizeStalling)
    }

    @Test
    func thePlayerIsBuiltOnceAndReusedUntilTornDown() throws {
        let url = try #require(URL(string: Constants.remoteURL))
        let playback = StreamingPlayback(url: url, fileExtension: Constants.fileExtension)

        let first = playback.player
        playback.tearDown()

        #expect(playback.player === first)
    }
}
