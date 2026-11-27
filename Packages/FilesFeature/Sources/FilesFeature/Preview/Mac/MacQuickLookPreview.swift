#if os(macOS)
    import DesignSystem
    import Quartz
    import SwiftUI
    import UniformTypeIdentifiers

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
            let url = urls.indices.contains(index) ? urls[index] : nil
            Group {
                if let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .svg) == true {
                    SVGItemView(url: url)
                } else {
                    QuickLookItemView(url: url)
                }
            }
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

    private struct SVGItemView: View {
        let url: URL

        @State private var image: NSImage?
        @State private var isLoaded = false

        var body: some View {
            ZStack {
                Color.clear
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(.space16)
                } else if isLoaded {
                    QuickLookItemView(url: url)
                }
            }
            .task(id: url) {
                image = NSImage(contentsOf: url)
                isLoaded = true
            }
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

    #Preview {
        QuickLookPreview(url: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"))
            .previewCanvas(.dialog)
    }

    #Preview("SVG") {
        QuickLookPreview(
            url: URL(
                fileURLWithPath: "/System/Library/PrivateFrameworks/BiometricKitUI.framework/Resources/drawing.svg"
            )
        )
        .previewCanvas(.dialog)
    }
#endif
