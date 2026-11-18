@testable import CoreModels
import Foundation
import Testing

@Suite("FFmpegSettings encoding")
struct FFmpegSettingsEncodingTests {
    private struct Case: Sendable {
        let ffmpeg: String
        let ffprobe: String
        let expectedFFmpeg: String?
        let expectedFFprobe: String?
    }

    private static let cases = [
        Case(ffmpeg: "", ffprobe: "", expectedFFmpeg: nil, expectedFFprobe: nil),
        Case(ffmpeg: "", ffprobe: "/usr/bin/ffprobe", expectedFFmpeg: nil, expectedFFprobe: "/usr/bin/ffprobe"),
        Case(ffmpeg: "/usr/bin/ffmpeg", ffprobe: "", expectedFFmpeg: "/usr/bin/ffmpeg", expectedFFprobe: nil),
        Case(
            ffmpeg: "/usr/bin/ffmpeg",
            ffprobe: "/usr/bin/ffprobe",
            expectedFFmpeg: "/usr/bin/ffmpeg",
            expectedFFprobe: "/usr/bin/ffprobe"
        ),
    ]

    @Test("an empty path is sent as null to clear the override and a set path as text", arguments: cases)
    private func emptyPathEncodesAsNull(_ testCase: Case) throws {
        let data = try JSONEncoder().encode(FFmpegSettings(ffmpegPath: testCase.ffmpeg, ffprobePath: testCase.ffprobe))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["ffmpegPath", "ffprobePath"])
        #expect(json["ffmpegPath"] as? String == testCase.expectedFFmpeg)
        #expect(json["ffprobePath"] as? String == testCase.expectedFFprobe)
        #expect((json["ffmpegPath"] is NSNull) == (testCase.expectedFFmpeg == nil))
        #expect((json["ffprobePath"] is NSNull) == (testCase.expectedFFprobe == nil))
    }
}
