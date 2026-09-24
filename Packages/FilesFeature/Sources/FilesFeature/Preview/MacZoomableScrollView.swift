#if os(macOS)
    import AppKit
    import SwiftUI

    private enum Constants {
        static let maximumZoomScale: CGFloat = 4
        static let doubleTapZoomScale: CGFloat = 2.5
    }

    /// macOS counterpart of the `UIScrollView` zoom container: `NSScrollView` magnification gives
    /// native trackpad pinch, and a double click toggles between fit and a fixed zoom level.
    struct ZoomableScrollView<Content: View>: NSViewRepresentable {
        private let content: Content
        private let onZoomChange: (Bool) -> Void

        init(onZoomChange: @escaping (Bool) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
            self.content = content()
            self.onZoomChange = onZoomChange
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.allowsMagnification = true
            scrollView.minMagnification = 1
            scrollView.maxMagnification = Constants.maximumZoomScale
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = false
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false

            let hostingView = context.coordinator.hostingView
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.documentView = hostingView
            NSLayoutConstraint.activate([
                hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
                hostingView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            ])

            let doubleClick = NSClickGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleClick(_:))
            )
            doubleClick.numberOfClicksRequired = 2
            scrollView.addGestureRecognizer(doubleClick)

            context.coordinator.observeMagnification(of: scrollView)
            return scrollView
        }

        func updateNSView(_: NSScrollView, context: Context) {
            context.coordinator.onZoomChange = onZoomChange
            context.coordinator.hostingView.rootView = content
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(hostingView: NSHostingView(rootView: content), onZoomChange: onZoomChange)
        }

        @MainActor
        final class Coordinator: NSObject {
            let hostingView: NSHostingView<Content>
            var onZoomChange: (Bool) -> Void
            private var lastReportedIsZoomed = false
            private var observer: NSObjectProtocol?

            init(hostingView: NSHostingView<Content>, onZoomChange: @escaping (Bool) -> Void) {
                self.hostingView = hostingView
                self.onZoomChange = onZoomChange
            }

            func observeMagnification(of scrollView: NSScrollView) {
                observer = NotificationCenter.default.addObserver(
                    forName: NSScrollView.didEndLiveMagnifyNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    MainActor.assumeIsolated {
                        guard let scrollView else { return }
                        self?.reportZoom(of: scrollView)
                    }
                }
            }

            @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
                guard let scrollView = recognizer.view as? NSScrollView else { return }
                let target: CGFloat
                if scrollView.magnification > scrollView.minMagnification {
                    target = scrollView.minMagnification
                    scrollView.animator().magnification = target
                } else {
                    target = Constants.doubleTapZoomScale
                    let point = recognizer.location(in: hostingView)
                    scrollView.animator().setMagnification(target, centeredAt: point)
                }
                reportZoom(of: scrollView, target: target)
            }

            private func reportZoom(of scrollView: NSScrollView, target: CGFloat? = nil) {
                let isZoomed = (target ?? scrollView.magnification) > scrollView.minMagnification
                guard isZoomed != lastReportedIsZoomed else { return }
                lastReportedIsZoomed = isZoomed
                onZoomChange(isZoomed)
            }
        }
    }
#endif
