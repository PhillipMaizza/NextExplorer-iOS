@testable import FilesFeature
import SwiftUI
import Testing

struct BrowseShortcutTests {
    @Test
    func modifiersReadInTheOrderTheMenuBarShows() {
        #expect(BrowseShortcut.newFolder.glyphs == "\u{21E7}\u{2318}N")
        #expect(BrowseShortcut.newFile.glyphs == "\u{2325}\u{2318}N")
        #expect(KeyboardShortcut("k", modifiers: [.command, .control, .option, .shift])
            .glyphs == "\u{2303}\u{2325}\u{21E7}\u{2318}K")
    }

    @Test
    func aPlainCommandShortcutShowsOneGlyph() {
        #expect(BrowseShortcut.paste.glyphs == "\u{2318}V")
    }
}
