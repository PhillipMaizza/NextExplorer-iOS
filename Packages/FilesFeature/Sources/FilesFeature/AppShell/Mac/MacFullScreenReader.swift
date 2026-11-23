#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacFullScreenReader: NSViewRepresentable {
        @Binding var isFullScreen: Bool

        func makeNSView(context _: Context) -> ReaderView {
            let view = ReaderView()
            view.onChange = { isFullScreen = $0 }
            return view
        }

        func updateNSView(_ view: ReaderView, context _: Context) {
            view.onChange = { isFullScreen = $0 }
        }

        final class ReaderView: NSView {
            var onChange: (Bool) -> Void = { _ in }
            private var observers: [NSObjectProtocol] = []

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                guard let window else { return }
                onChange(window.styleMask.contains(.fullScreen))
                observers = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification]
                    .map { name in
                        NotificationCenter.default
                            .addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                                MainActor.assumeIsolated {
                                    guard let self, let window = self.window else { return }
                                    self.onChange(window.styleMask.contains(.fullScreen))
                                }
                            }
                    }
            }
        }
    }

    private struct FullScreenPreview: View {
        @State private var isFullScreen = false

        var body: some View {
            Text(verbatim: isFullScreen ? "Full screen" : "Windowed")
                .padding(.space48)
                .background { MacFullScreenReader(isFullScreen: $isFullScreen) }
        }
    }

    #Preview("Full screen reader") {
        FullScreenPreview()
    }
#endif
