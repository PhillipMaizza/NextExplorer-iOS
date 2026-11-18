import DesignSystem
@testable import FilesFeature
import SwiftUI
import Testing
import TestUtils

struct FileKindChipTests {
    @Test
    func anExtensionAlwaysPicksTheSameColour() {
        #expect(FileTypeIcon.paletteIndex(forKind: "exe") == 4)
        #expect(FileTypeIcon.paletteIndex(forKind: "EXE") == 4)
        #expect(FileTypeIcon.paletteIndex(forKind: "bin") == 1)
    }

    @Test
    func aKindTooDarkToReadTakesAPaletteColourAndJavaArchivesTakeTheArchiveColour() {
        #expect(FileTypeIcon.color(forKind: "exe") == Color(hex: 0x6366F1))
        #expect(FileTypeIcon.color(forKind: "jar") == Color(hex: 0xF59E0B))
        #expect(FileTypeIcon.color(forKind: "") == Color.secondaryDS)
    }
}
