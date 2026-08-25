import SwiftUI

/// Semantic color tokens, extended directly on `Color` rather than wrapped in a
/// namespace type. Light/dark comes from the asset catalog's appearance variants.
public extension Color {
    /// Actionable items (links, selected picker segment).
    static let accent = Color("Accent", bundle: .module)
    /// Primary text/icons.
    static let primaryDS = Color("TextPrimary", bundle: .module)
    /// Secondary text, placeholders, subtitles.
    static let secondaryDS = Color("TextSecondary", bundle: .module)
    /// Positive/success feedback.
    static let positive = Color("Success", bundle: .module)
    /// Warning/attention feedback.
    static let attention = Color("Warning", bundle: .module)
    /// Negative/error feedback.
    static let negative = Color("Danger", bundle: .module)
    /// Default screen background.
    static let backgroundPrimary = Color("Background", bundle: .module)
    /// Secondary surface background (cards, grouped rows).
    static let backgroundSecondary = Color("Surface", bundle: .module)
    /// Default element divider/border (input fields, dividers).
    static let borderPrimary = Color("Border", bundle: .module)
}

/// Full tonal ramp mixed from `Color.accent` (toward white for tints, toward black for
/// shades) and from `Color.backgroundPrimary` (toward black), for cases the nine semantic
/// roles above don't cover — chart series, hover/pressed states, elevation layers, etc.
/// Reach for a semantic role first; drop to a raw step only when nothing semantic fits.
public extension Color {
    static let accent50 = Color("Accent50", bundle: .module)
    static let accent100 = Color("Accent100", bundle: .module)
    static let accent200 = Color("Accent200", bundle: .module)
    static let accent300 = Color("Accent300", bundle: .module)
    static let accent400 = Color("Accent400", bundle: .module)
    /// Same value as `Color.accent` — included so the 50–900 ramp reads as one continuous scale.
    static let accent500 = Color("Accent", bundle: .module)
    static let accent600 = Color("Accent600", bundle: .module)
    static let accent700 = Color("Accent700", bundle: .module)
    static let accent800 = Color("Accent800", bundle: .module)
    static let accent900 = Color("Accent900", bundle: .module)

    static let neutral50 = Color("Neutral50", bundle: .module)
    static let neutral100 = Color("Neutral100", bundle: .module)
    static let neutral200 = Color("Neutral200", bundle: .module)
    static let neutral300 = Color("Neutral300", bundle: .module)
    static let neutral400 = Color("Neutral400", bundle: .module)
    static let neutral500 = Color("Neutral500", bundle: .module)
    static let neutral600 = Color("Neutral600", bundle: .module)
    static let neutral700 = Color("Neutral700", bundle: .module)
    static let neutral800 = Color("Neutral800", bundle: .module)
    static let neutral900 = Color("Neutral900", bundle: .module)
}
