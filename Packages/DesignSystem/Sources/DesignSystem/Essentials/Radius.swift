import CoreGraphics

/// Corner-radius tokens.
public extension CGFloat {
    /// 0pt — no rounding.
    static let radiusNone: CGFloat = 0
    /// 4pt — extra small rounding, used for tags.
    static let radiusXSmall: CGFloat = 4
    /// 8pt — small rounding, used for input fields.
    static let radiusSmall: CGFloat = 8
    /// 12pt — matches the web client's auth inputs/buttons.
    static let radiusControl: CGFloat = 12
    /// 16pt — medium rounding, used for cards and sheets.
    static let radiusMedium: CGFloat = 16
    /// 24pt — large rounding, used for large containers.
    static let radiusLarge: CGFloat = 24
    /// 10000pt — effectively circular; use for pills and chips.
    static let radiusFull: CGFloat = 10000

    /// The corner radius for cards and other filled containers: `radiusLarge` on iOS 26, to
    /// sit with Liquid Glass's rounder language, `radiusMedium` below it. Use this rather than
    /// a fixed token so every card tracks the platform together.
    static var radiusCard: CGFloat {
        if #available(iOS 26.0, *) {
            .radiusLarge
        } else {
            .radiusMedium
        }
    }

    /// The corner radius for search fields: `radiusLarge` on iOS 26, to match Liquid Glass's
    /// rounder search bars, `radiusControl` below it. Use this rather than a fixed token so every
    /// search field tracks the platform together.
    static var radiusSearchField: CGFloat {
        if #available(iOS 26.0, *) {
            .radiusLarge
        } else {
            .radiusControl
        }
    }
}
