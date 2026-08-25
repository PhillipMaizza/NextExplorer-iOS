import SwiftUI

/// Shadow tiers for surfaces that should read as raised above the background. Values are
/// ported directly from FreeNow's `Elevations.swift` (two stacked shadow layers, dark navy
/// base color) — a tight, discreet lift rather than a broad, soft glow.
public enum Elevation: CaseIterable {
    /// No shadow.
    case level0
    /// Subtlest lift — floating buttons.
    case level1
    /// Cards, sticky bars, menus.
    case level4
    /// Map-style overlay buttons, tooltips.
    case level8
    /// Bottom sheets, pickers, dialogs.
    case level16

    fileprivate struct ShadowLayer {
        let y: CGFloat
        let blur: CGFloat
    }

    fileprivate var firstShadow: ShadowLayer {
        switch self {
        case .level0: ShadowLayer(y: 0, blur: 0)
        case .level1: ShadowLayer(y: 0, blur: 2)
        case .level4: ShadowLayer(y: 0, blur: 2)
        case .level8: ShadowLayer(y: 4, blur: 12)
        case .level16: ShadowLayer(y: 8, blur: 24)
        }
    }

    fileprivate var secondShadow: ShadowLayer {
        switch self {
        case .level0: ShadowLayer(y: 0, blur: 0)
        case .level1: ShadowLayer(y: 1, blur: 1)
        case .level4: ShadowLayer(y: 4, blur: 6)
        case .level8: ShadowLayer(y: 8, blur: 16)
        case .level16: ShadowLayer(y: 16, blur: 32)
        }
    }

    /// Dark navy shadow base, matching FreeNow's `#000F1F`.
    fileprivate static let shadowColor = Color(red: 0, green: 15.0 / 255.0, blue: 31.0 / 255.0)
}

public extension View {
    /// Applies the design system's two-layer elevation shadow.
    func elevation(_ level: Elevation, alpha: Double = 0.25) -> some View {
        self
            .shadow(color: Elevation.shadowColor.opacity(alpha), radius: level.firstShadow.blur / 2, x: 0, y: level.firstShadow.y)
            .shadow(color: Elevation.shadowColor.opacity(alpha), radius: level.secondShadow.blur / 2, x: 0, y: level.secondShadow.y)
    }
}
