#if os(macOS)
    import AppKit
    import SwiftUI

    public extension View {
        /// Frosts the whole window: the desktop and the windows behind it show through, blurred,
        /// in light and dark alike, the way Finder's sidebar does. Content that paints its own
        /// background (the file list) stays solid on top. Reduce Transparency turns the blur into
        /// the system's opaque fill on its own.
        func macFrostedWindow() -> some View {
            background(MacFrostedWindowBackground().ignoresSafeArea())
        }
    }

    private struct MacFrostedWindowBackground: NSViewRepresentable {
        func makeNSView(context _: Context) -> FrostView {
            let view = FrostView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        func updateNSView(_: FrostView, context _: Context) {}

        /// The blur only shows through a window that is not opaque, so the hosting window is
        /// made see through as soon as the view lands in it, and its title bar lets the glass run up under it.
        final class FrostView: NSVisualEffectView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                window?.isOpaque = false
                window?.backgroundColor = .clear
                window?.titlebarAppearsTransparent = true
            }
        }
    }

    #Preview("Frosted window") {
        Text(verbatim: "Content over the window's frost")
            .padding(48)
            .macFrostedWindow()
    }
#endif
