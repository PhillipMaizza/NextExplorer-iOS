#if os(macOS)
    import SwiftUI

    public extension View {
        /// For a prompt that several Mac windows host (the main window and the Settings window):
        /// each time `isPending` changes, reports whether this window owns it, which is the
        /// window that was active when the prompt was raised. So it never shows twice, or opens
        /// behind the window the person is looking at.
        func onWindowPromptChange(
            of isPending: Bool,
            perform action: @escaping (_ isPending: Bool, _ isOwner: Bool) -> Void
        ) -> some View {
            modifier(WindowPromptOwner(isPending: isPending, action: action))
        }
    }

    private struct WindowPromptOwner: ViewModifier {
        let isPending: Bool
        let action: (Bool, Bool) -> Void
        @Environment(\.appearsActive) private var appearsActive

        func body(content: Content) -> some View {
            content.onChange(of: isPending) { _, pending in
                action(pending, pending && appearsActive)
            }
        }
    }

    #Preview {
        @Previewable @State var isOwner = false
        Text(verbatim: isOwner ? "This window owns the prompt" : "Waiting for a prompt")
            .padding(.space24)
            .onWindowPromptChange(of: true) { _, owner in isOwner = owner }
    }
#endif
