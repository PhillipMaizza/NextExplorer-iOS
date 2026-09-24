#if os(iOS)
    import SwiftUI
    import UIKit

    private enum Constants {
        static let maximumZoomScale: CGFloat = 4
        static let doubleTapZoomScale: CGFloat = 2.5
    }

    /// Pinch and double tap zoom for a single piece of content, backed by `UIScrollView` so pan
    /// and zoom feel native. Scrolling stays disabled at `zoomScale == 1`, so the parent
    /// `TabView` paging and swipe to dismiss keep their gestures until the user actually zooms in.
    ///
    /// `onZoomChange` fires whenever the content crosses between "fits" (`zoomScale == minimum`)
    /// and "zoomed in" — the parent uses it to suspend its own swipe-to-dismiss drag while the
    /// user is panning around a magnified image.
    struct ZoomableScrollView<Content: View>: UIViewRepresentable {
        private let content: Content
        private let onZoomChange: (Bool) -> Void

        init(onZoomChange: @escaping (Bool) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
            self.content = content()
            self.onZoomChange = onZoomChange
        }

        func makeUIView(context: Context) -> UIScrollView {
            let scrollView = UIScrollView()
            scrollView.delegate = context.coordinator
            scrollView.maximumZoomScale = Constants.maximumZoomScale
            scrollView.minimumZoomScale = 1
            scrollView.bouncesZoom = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.isScrollEnabled = false
            scrollView.backgroundColor = .clear

            let hostedView = context.coordinator.hostingController.view!
            hostedView.translatesAutoresizingMaskIntoConstraints = false
            hostedView.backgroundColor = .clear
            scrollView.addSubview(hostedView)
            NSLayoutConstraint.activate([
                hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])

            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTap(_:))
            )
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            return scrollView
        }

        func updateUIView(_: UIScrollView, context: Context) {
            context.coordinator.onZoomChange = onZoomChange
            context.coordinator.hostingController.rootView = content
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(hostingController: UIHostingController(rootView: content), onZoomChange: onZoomChange)
        }

        final class Coordinator: NSObject, UIScrollViewDelegate {
            let hostingController: UIHostingController<Content>
            var onZoomChange: (Bool) -> Void
            private var lastReportedIsZoomed = false

            init(hostingController: UIHostingController<Content>, onZoomChange: @escaping (Bool) -> Void) {
                self.hostingController = hostingController
                self.onZoomChange = onZoomChange
            }

            func viewForZooming(in _: UIScrollView) -> UIView? {
                hostingController.view
            }

            func scrollViewDidZoom(_ scrollView: UIScrollView) {
                let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale
                scrollView.isScrollEnabled = isZoomed
                guard isZoomed != lastReportedIsZoomed else { return }
                lastReportedIsZoomed = isZoomed
                let notify = onZoomChange
                DispatchQueue.main.async { notify(isZoomed) }
            }

            @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
                guard let scrollView = recognizer.view as? UIScrollView else { return }
                if scrollView.zoomScale > scrollView.minimumZoomScale {
                    scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                } else {
                    let center = recognizer.location(in: hostingController.view)
                    let scaledSize = CGSize(
                        width: scrollView.bounds.width / Constants.doubleTapZoomScale,
                        height: scrollView.bounds.height / Constants.doubleTapZoomScale
                    )
                    scrollView.zoom(
                        to: CGRect(
                            x: center.x - scaledSize.width / 2,
                            y: center.y - scaledSize.height / 2,
                            width: scaledSize.width,
                            height: scaledSize.height
                        ),
                        animated: true
                    )
                }
            }
        }
    }
#endif
