@testable import CoreModels
import Testing

@Suite("UploadMode")
struct UploadModeTests {
    private static let mebibyte = UploadSettings.bytesPerMiB

    @Test("No settings or no chunking goes direct")
    func directByDefault() {
        #expect(UploadMode.resolve(settings: nil, rememberedMiB: 32) == .direct)
        #expect(UploadMode.resolve(settings: UploadSettings(), rememberedMiB: nil) == .direct)
    }

    @Test("Forced chunking wins over a remembered size")
    func forcedChunking() {
        let settings = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 4 * Self.mebibyte)
        #expect(UploadMode
            .resolve(settings: settings, rememberedMiB: 32) == .chunked(chunkSizeBytes: 4 * Self.mebibyte))
    }

    @Test("A remembered size is used only when auto fallback is on")
    func rememberedSize() {
        let allowed = UploadSettings(isChunkedAutoFallback: true)
        #expect(UploadMode
            .resolve(settings: allowed, rememberedMiB: 16) == .chunked(chunkSizeBytes: 16 * Self.mebibyte))
        #expect(UploadMode.resolve(settings: UploadSettings(), rememberedMiB: 16) == .direct)
    }

    @Test("The ladder starts below the refused size and steps down to the end")
    func ladder() {
        #expect(UploadMode.nextFallbackMiB(current: nil, refusedBytes: 100 * Self.mebibyte) == 96)
        #expect(UploadMode.nextFallbackMiB(current: nil, refusedBytes: 50 * Self.mebibyte) == 32)
        #expect(UploadMode.nextFallbackMiB(current: nil, refusedBytes: 1024) == 96)
        #expect(UploadMode.nextFallbackMiB(current: 96, refusedBytes: 0) == 64)
        #expect(UploadMode.nextFallbackMiB(current: 16, refusedBytes: 0) == 8)
        #expect(UploadMode.nextFallbackMiB(current: 8, refusedBytes: 0) == nil)
    }
}
