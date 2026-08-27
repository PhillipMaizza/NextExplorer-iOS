import SwiftUI

public extension Color {
    /// Hand-tuned categorical swatches for labelling distinct entities (recipient names,
    /// tags) — each one stays legible as both a chip tint (~15% alpha fill) and the chip's
    /// text color in light and dark mode. Not derived from the accent/neutral ramps: those
    /// only span one hue, so adjacent chips wouldn't read as different.
    static let categoricalPalette: [Color] = [
        Color(red: 0.40, green: 0.52, blue: 0.92),
        Color(red: 0.30, green: 0.67, blue: 0.61),
        Color(red: 0.86, green: 0.52, blue: 0.30),
        Color(red: 0.80, green: 0.42, blue: 0.62),
        Color(red: 0.50, green: 0.62, blue: 0.33),
        Color(red: 0.58, green: 0.47, blue: 0.85),
        Color(red: 0.88, green: 0.45, blue: 0.45),
        Color(red: 0.33, green: 0.60, blue: 0.80),
    ]

    /// Stable palette entry for `key` — the same string always maps to the same swatch, so a
    /// person keeps their color across rows and app launches. Rolls its own hash: `Hashable`
    /// is seeded per process and would hand out a different color every launch.
    static func categorical(for key: String) -> Color {
        let hash = key.unicodeScalars.reduce(into: UInt64(5_381)) { $0 = ($0 &* 33) &+ UInt64($1.value) }
        return categoricalPalette[Int(hash % UInt64(categoricalPalette.count))]
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(["Jamie Rivera", "Sam Okafor", "Jeremy Brown", "Dana Lee", "Priya Nair", "Marco Bianchi", "Alex Kim", "Wei Zhang"], id: \.self) { name in
            Text(name)
                .type(.body2(.semibold))
                .foregroundStyle(Color.categorical(for: name))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.categorical(for: name).opacity(0.16)))
        }
    }
    .padding()
}
