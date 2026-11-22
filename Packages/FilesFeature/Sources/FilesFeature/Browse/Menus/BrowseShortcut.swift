import SwiftUI

public enum BrowseShortcut {
    public static let newFolder = KeyboardShortcut("n", modifiers: [.command, .shift])
    public static let newFile = KeyboardShortcut("n", modifiers: [.command, .option])
    public static let paste = KeyboardShortcut("v")
}

extension KeyboardShortcut {
    var glyphs: String {
        let marks: [(modifier: EventModifiers, glyph: String)] = [
            (.control, "\u{2303}"),
            (.option, "\u{2325}"),
            (.shift, "\u{21E7}"),
            (.command, "\u{2318}"),
        ]
        let prefix = marks.filter { modifiers.contains($0.modifier) }.map(\.glyph).joined()
        return prefix + String(key.character).uppercased()
    }
}
