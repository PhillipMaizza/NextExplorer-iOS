@testable import FilesClient
import Foundation
import Testing

struct TextDecodingTests {
    private func bytes(_ values: [UInt8]) -> Data {
        Data(values)
    }

    @Test
    func aUTF8ByteOrderMarkIsStripped() {
        let data = bytes([0xEF, 0xBB, 0xBF]) + Data("héllo".utf8)
        #expect(FilesService.decodeText(data) == "héllo")
    }

    @Test
    func aUTF16LittleEndianFileWithAMarkDecodesAsUTF16NotLatin1() throws {
        let body = try #require("héllo wörld".data(using: .utf16LittleEndian))
        #expect(FilesService.decodeText(bytes([0xFF, 0xFE]) + body) == "héllo wörld")
    }

    @Test
    func aUTF16BigEndianFileWithAMarkDecodes() throws {
        let body = try #require("héllo".data(using: .utf16BigEndian))
        #expect(FilesService.decodeText(bytes([0xFE, 0xFF]) + body) == "héllo")
    }

    @Test
    func aUTF32LittleEndianMarkIsNotMistakenForUTF16() throws {
        let body = try #require("héllo".data(using: .utf32LittleEndian))
        #expect(FilesService.decodeText(bytes([0xFF, 0xFE, 0x00, 0x00]) + body) == "héllo")
    }

    @Test
    func aUTF32BigEndianFileDecodes() throws {
        let body = try #require("héllo".data(using: .utf32BigEndian))
        #expect(FilesService.decodeText(bytes([0x00, 0x00, 0xFE, 0xFF]) + body) == "héllo")
    }

    @Test
    func aMarklessUTF16LittleEndianASCIIFileDecodesInsteadOfBecomingNulSeparatedText() throws {
        let data = try #require("hello world".data(using: .utf16LittleEndian))
        #expect(FilesService.decodeText(data) == "hello world")
    }

    @Test
    func aMarklessUTF16BigEndianASCIIFileDecodes() throws {
        let data = try #require("hello world".data(using: .utf16BigEndian))
        #expect(FilesService.decodeText(data) == "hello world")
    }

    @Test
    func strictUTF8WinsForValidMultibyteText() {
        #expect(FilesService.decodeText(Data("naïve ✓ 日本語".utf8)) == "naïve ✓ 日本語")
    }

    @Test
    func invalidUTF8FallsBackToWindows1252WithItsExtraPunctuation() {
        // 0x80 is the euro sign and 0x93/0x94 are curly quotes in Windows 1252, controls in Latin-1.
        let data = bytes([0x80, 0x20, 0x93, 0x63, 0x61, 0x66, 0xE9, 0x94])
        #expect(FilesService.decodeText(data) == "€ “café”")
    }

    @Test
    func anEvenLengthLatin1FileIsNotDecodedAsUTF16Garbage() {
        let data = bytes([0x61, 0x62, 0xE9, 0xE9])
        #expect(FilesService.decodeText(data) == "abéé")
    }

    @Test
    func bytesUndefinedInWindows1252ThatLatin1TurnsIntoControlsAreRejectedAsNotText() {
        let data = bytes([0x61, 0x81, 0x62])
        #expect(FilesService.decodeText(data) == nil)
    }

    @Test
    func aMarkThenALoneSurrogateIsNotTextBecauseItsLegacyReadingHoldsANul() {
        #expect(FilesService.decodeText(bytes([0xFF, 0xFE, 0x00, 0xD8])) == nil)
    }

    @Test
    func utf8WithANulIsBinaryNotText() {
        #expect(FilesService.decodeText(Data("hello world, this is text\0\0 and more text after it".utf8)) == nil)
    }

    @Test
    func aPNGHeaderIsBinaryNotText() {
        #expect(FilesService.decodeText(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == nil)
    }

    @Test
    func tabsAndLineBreaksAreStillPlainText() {
        #expect(FilesService.decodeText(Data("a\tb\r\nc\n".utf8)) == "a\tb\r\nc\n")
    }

    @Test
    func emptyDataIsEmptyText() {
        #expect(FilesService.decodeText(Data()) == "")
    }

    @Test
    func aSingleByteIsNotTreatedAsUTF16() {
        #expect(FilesService.decodeText(bytes([0x41])) == "A")
    }

    @Test
    func aMarkFollowedByInvalidBytesFallsThroughToWindows1252() {
        let utf8Mark = bytes([0xEF, 0xBB, 0xBF, 0x63, 0x61, 0x66, 0xE9])
        #expect(FilesService.decodeText(utf8Mark) == "café")
    }

    @Test
    func marklessUTF16OfCJKTextDecodesInBothByteOrders() throws {
        let text = "你好世界，这是一个没有字节顺序标记的测试文件"
        #expect(try FilesService.decodeText(#require(text.data(using: .utf16LittleEndian))) == text)
        #expect(try FilesService.decodeText(#require(text.data(using: .utf16BigEndian))) == text)
    }

    @Test
    func marklessUTF16OfCyrillicTextDecodes() throws {
        let text = "Привет, мир! Это тестовый файл без метки порядка байтов."
        #expect(try FilesService.decodeText(#require(text.data(using: .utf16LittleEndian))) == text)
        #expect(try FilesService.decodeText(#require(text.data(using: .utf16BigEndian))) == text)
    }

    @Test
    func latin1TextWithAccentsIsNeverTakenForUTF16() throws {
        for text in ["Café au lait, crème brûlée et œufs", "Größe: 10 Straße, schön", "ab éé", "Señor Núñez said hello"] {
            let data = try #require(text.data(using: .windowsCP1252))
            #expect(FilesService.decodeText(data) == text)
        }
    }

    @Test
    func randomBinaryDataIsNeverTakenForUTF16() {
        var generator = SplitMix64(seed: 0x5EED)
        for _ in 0 ..< 200 {
            let length = Int(generator.next() % 64) * 2 + 8
            let data = Data((0 ..< length).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
            guard String(data: data, encoding: .utf8) == nil, !data.contains(0) else { continue }
            let legacy = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
            let decoded = FilesService.decodeText(data)
            #expect(decoded == nil || decoded == legacy)
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
