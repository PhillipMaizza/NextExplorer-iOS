#if os(macOS)
    import SwiftUI

    public extension View {
        /// For a prompt that several Mac windows host (the main window and the Settings window):
        /// reports whether this window owns it, which is the window that was active when the
        /// prompt was raised, or the first one to become active while it waits unowned. So it
        /// never shows twice, opens behind the window the person is looking at, or gets lost.
        func onWindowPromptChange(
            for prompt: Any.Type,
            of isPending: Bool,
            perform action: @escaping (_ isPending: Bool, _ isOwner: Bool) -> Void
        ) -> some View {
            modifier(WindowPromptOwner(prompt: ObjectIdentifier(prompt), isPending: isPending, action: action))
        }
    }

    @MainActor
    private enum WindowPromptClaims {
        static var claimed: Set<ObjectIdentifier> = []
    }

    private struct WindowPromptOwner: ViewModifier {
        let prompt: ObjectIdentifier
        let isPending: Bool
        let action: (Bool, Bool) -> Void
        @Environment(\.appearsActive) private var appearsActive
        @State private var isOwner = false

        func body(content: Content) -> some View {
            content
                .onChange(of: isPending) { _, pending in
                    if pending {
                        action(true, claim())
                    } else {
                        release()
                        action(false, false)
                    }
                }
                .onChange(of: appearsActive) { _, active in
                    guard active, isPending, !isOwner, claim() else { return }
                    action(true, true)
                }
                .onDisappear(perform: release)
        }

        private func claim() -> Bool {
            guard appearsActive, !WindowPromptClaims.claimed.contains(prompt) else { return false }
            WindowPromptClaims.claimed.insert(prompt)
            isOwner = true
            return true
        }

        private func release() {
            guard isOwner else { return }
            isOwner = false
            WindowPromptClaims.claimed.remove(prompt)
        }
    }

    #Preview {
        @Previewable @State var isOwner = false
        Text(verbatim: isOwner ? "This window owns the prompt" : "Waiting for a prompt")
            .padding(.space24)
            .onWindowPromptChange(for: Text.self, of: true) { _, owner in isOwner = owner }
    }
#endif
