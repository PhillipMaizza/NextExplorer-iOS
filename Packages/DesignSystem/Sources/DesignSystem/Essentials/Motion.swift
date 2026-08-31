import SwiftUI

/// Shared animation tokens for list screens, so Browse / Favorites / Downloads / Shared
/// cross-fade and reorder identically instead of each carrying its own copy of the numbers.
public enum DSMotion {
    /// Skeleton → content (and any list-state) cross-fade.
    public static let contentRevealDuration: Double = 0.3

    /// The cross-fade animation itself.
    public static var contentReveal: Animation {
        .easeInOut(duration: contentRevealDuration)
    }

    /// Row insert / remove / reorder inside a settled list.
    public static var listDiff: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// A disclosure row expanding / collapsing (chevron rotation + body reveal).
    public static var disclosure: Animation {
        .spring(response: 0.3, dampingFraction: 0.78)
    }
}
