import SwiftUI

public extension View {
    /// The accessibility label for an icon only control, which on macOS is also shown as its
    /// hover tooltip (a Mac user has no other way to learn what an unlabeled icon does).
    func accessibilityLabelWithTooltip(_ label: String) -> some View {
        #if os(macOS)
            accessibilityLabel(label).help(label)
        #else
            accessibilityLabel(label)
        #endif
    }
}
