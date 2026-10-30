import SwiftUI

public extension View {
    /// A page's main action (Save, Update, Submit). Full width on iOS as the button lays itself
    /// out; on the Mac it sits at the trailing edge, where a native form puts its default button.
    func formActionAlignment() -> some View {
        #if os(macOS)
            frame(maxWidth: .infinity, alignment: .trailing)
        #else
            self
        #endif
    }
}
