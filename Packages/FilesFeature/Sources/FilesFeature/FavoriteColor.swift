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

        /// Black on a light swatch, white on a dark one — so the selection ring stays visible
        /// whatever the fill. Perceptual luma (`0.299R 0.587G 0.114B`), threshold at mid grey.
        var ring: Color {
            let r = Double((fill >> 16) & 0xFF)
            let g = Double((fill >> 8) & 0xFF)
            let b = Double(fill & 0xFF)
            return (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? .black : .white
        }
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
