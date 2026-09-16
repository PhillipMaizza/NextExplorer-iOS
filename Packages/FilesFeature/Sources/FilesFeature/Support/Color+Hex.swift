import SwiftUI

extension Color {
    /// `0xRRGGBB` literal, for palettes kept as raw hex to match the web client.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// `"#rrggbb"` or `"rrggbb"` string (as the backend stores a favorite's colour).
    /// `nil` for anything that isn't a 6-digit hex.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
