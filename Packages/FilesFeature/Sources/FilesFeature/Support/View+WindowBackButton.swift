import SwiftUI

extension View {
    func hidesSystemBackOnMac() -> some View {
        #if os(macOS)
            navigationBarBackButtonHidden()
        #else
            self
        #endif
    }
}

extension View {
    func instantPushOnMac(depth: Int) -> some View {
        #if os(macOS)
            transaction(value: depth) { $0.disablesAnimations = true }
                .environment(\.macStackDepth, depth)
        #else
            self
        #endif
    }
}

#if os(macOS)
    extension EnvironmentValues {
        @Entry var macStackDepth = 0
    }

    private struct FocusWhenOnTop: ViewModifier {
        let isFocused: FocusState<Bool>.Binding

        @Environment(\.macStackDepth) private var stackDepth
        @State private var ownDepth: Int?

        func body(content: Content) -> some View {
            content
                .onAppear {
                    ownDepth = ownDepth ?? stackDepth
                    focus()
                }
                .onChange(of: stackDepth) { _, depth in
                    guard depth == ownDepth else { return }
                    focus()
                }
        }

        private func focus() {
            Task { isFocused.wrappedValue = true }
        }
    }

    extension View {
        func focusedWhenOnTop(_ isFocused: FocusState<Bool>.Binding) -> some View {
            modifier(FocusWhenOnTop(isFocused: isFocused))
        }
    }
#endif
