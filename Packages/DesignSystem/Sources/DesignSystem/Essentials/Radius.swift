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
}
