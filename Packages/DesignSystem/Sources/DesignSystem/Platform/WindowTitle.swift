#if os(macOS)
    import AppKit
    import SwiftUI

    public extension View {
        /// Sets the hosting window's title, shown in its toolbar like Finder's folder name and on
        /// its tab. For screens that leave the system navigation title empty.
        func windowTitle(_ title: String) -> some View {
            background(WindowTitleSetter(title: title))
        }
    }

    private struct WindowTitleSetter: NSViewRepresentable {
        let title: String

        func makeNSView(context _: Context) -> TitleView {
            TitleView(title: title)
        }

        func updateNSView(_ view: TitleView, context _: Context) {
            view.title = title
        }

        final class TitleView: NSView {
            var title: String {
                didSet { apply() }
            }

            init(title: String) {
                self.title = title
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            /// SwiftUI resets the title from the (deliberately empty) navigation title after we set
            /// it, so the window is watched and our title put back whenever it drifts.
            private var observation: NSKeyValueObservation?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observation = window?.observe(\.title, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.apply() }
                }
                apply()
            }

            private func apply() {
                guard let window, window.title != title else { return }
                window.title = title
            }
        }
    }
#endif
