#if os(macOS)
    import Quartz
    import SwiftUI

    /// macOS counterpart of the `QLPreviewController` wrapper. `QLPreviewView` renders one item
    /// at a time, so paging between several URLs is driven here with the arrow keys.
    struct QuickLookPreview: View {
        let urls: [URL]
        var onIndexChange: (@MainActor (Int) -> Void)?

        @State private var index: Int

        init(urls: [URL], initialIndex: Int = 0, onIndexChange: (@MainActor (Int) -> Void)? = nil) {
            self.urls = urls
            self.onIndexChange = onIndexChange
            _index = State(initialValue: urls.indices.contains(initialIndex) ? initialIndex : 0)
        }

        init(url: URL) {
            self.init(urls: [url])
        }

        var body: some View {
            QuickLookItemView(url: urls.indices.contains(index) ? urls[index] : nil)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { step(by: -1) }
                .onKeyPress(.rightArrow) { step(by: 1) }
        }

        private func step(by offset: Int) -> KeyPress.Result {
            let next = index + offset
            guard urls.indices.contains(next) else { return .ignored }
            index = next
            onIndexChange?(next)
            return .handled
        }
    }

    private struct QuickLookItemView: NSViewRepresentable {
        let url: URL?

        func makeNSView(context _: Context) -> QLPreviewView {
            let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
            view.autostarts = true
            view.previewItem = url as NSURL?
            return view
        }

        func updateNSView(_ view: QLPreviewView, context _: Context) {
            // Only swap on a real change so a rerender doesn't reset the reader's scroll or zoom.
            guard (view.previewItem as? NSURL) as URL? != url else { return }
            view.previewItem = url as NSURL?
        }

        static func dismantleNSView(_ view: QLPreviewView, coordinator _: ()) {
            view.close()
        }
    }
#endif
