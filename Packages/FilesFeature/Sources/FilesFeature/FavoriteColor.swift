import SwiftUI

/// The favorite-colour swatches, mirroring `FavoriteEditDialog.vue`'s `COLOR_PALETTE`. The
/// stored value is a `"#rrggbb"` string (or `nil` for the default); anything the palette
/// doesn't recognise still renders via `Color(hexString:)`.
enum FavoriteColor {
    struct Swatch: Identifiable, Equatable {
        let hex: String
        let fill: UInt32

        var id: String { hex }
        var color: Color { Color(hex: fill) }
    }

    static let palette: [Swatch] = [
        Swatch(hex: "#ff5e5a", fill: 0xFF5E5A),
        Swatch(hex: "#ffb000", fill: 0xFFB000),
        Swatch(hex: "#ffde00", fill: 0xFFDE00),
        Swatch(hex: "#0bd336", fill: 0x0BD336),
        Swatch(hex: "#009cff", fill: 0x009CFF),
        Swatch(hex: "#d873fb", fill: 0xD873FB),
    ]

    /// The colour a favorite's icon is tinted with. `nil` when no colour is set — the caller
    /// falls back to `Color.accent`.
    static func resolve(_ hex: String?) -> Color? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if let swatch = palette.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) {
            return swatch.color
        }
        return Color(hexString: hex)
    }

    /// Whether `stored` refers to the same swatch as `hex` (case-insensitive, both optional).
    static func matches(_ stored: String?, _ hex: String?) -> Bool {
        switch (stored?.lowercased(), hex?.lowercased()) {
        case (nil, nil): return true
        case let (a?, b?): return a == b
        default: return false
        }
    }
}
