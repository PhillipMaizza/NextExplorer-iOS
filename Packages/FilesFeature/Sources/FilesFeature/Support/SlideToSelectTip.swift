#if os(iOS)
    import DesignSystem
    import Localization
    import SwiftUI
    import TipKit

    /// Teaches slide to select, which nothing on screen shows: it points at the selection count as
    /// select mode opens, until it is dismissed or the first slide makes it pointless.
    struct SlideToSelectTip: Tip {
        var title: Text {
            Text(L10n.Select.slideTipTitle)
        }

        var message: Text? {
            Text(L10n.Select.slideTipMessage)
        }

        var image: Image? {
            IconKit.checkmarkCircleFill
        }

        /// The slide was used, so the tip has nothing left to teach.
        @MainActor private static var isInvalidated = false

        @MainActor
        static func slideUsed() {
            guard !isInvalidated else { return }
            isInvalidated = true
            SlideToSelectTip().invalidate(reason: .actionPerformed)
        }
    }
#endif
