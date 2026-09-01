import SwiftUI
import UIKit

public extension View {
    /// Resigns the first responder (dismisses the keyboard) when this view is tapped — e.g.
    /// tapping the empty space of a list while a search field is focused. Uses a
    /// `simultaneousGesture` so the tap still reaches any button/row underneath, and a global
    /// `resignFirstResponder` so the caller doesn't need to thread the field's focus binding
    /// down to the list. Apply to the scrolling content only, never over the search field
    /// itself (that would defocus it on the same tap that focuses it).
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
        )
    }
}
