#if os(macOS)
    import AppKit
    import DesignSystem
    import SwiftUI

    private enum Constants {
        static let maximumZoomScale: CGFloat = 4
        static let doubleTapZoomScale: CGFloat = 2.5
        /// Each Zoom In or Zoom Out multiplies or divides the magnification by this much.
        static let zoomStepFactor: CGFloat = 1.25
    }

    /// One step of View ▸ Zoom In, Zoom Out or Zoom to Fit.
    enum MacZoomStep {
        case zoomIn, zoomOut, fit
    }

    /// Drives the `ZoomableScrollView` on screen from outside it: the View menu's zoom items and
    /// VoiceOver's zoom action reach the scroll view through this.
    @MainActor
    final class MacZoomController {
        private var handler: ((MacZoomStep) -> Void)?

        func attach(_ handler: @escaping (MacZoomStep) -> Void) {
            self.handler = handler
        }

        func zoom(_ step: MacZoomStep) {
            handler?(step)
        }
    }

    extension EnvironmentValues {
        @Entry var macZoomController: MacZoomController?
    }

    /// ⌘+, ⌘− and ⌘0 for the image preview on screen, published by `MacPreviewZoom`.
    public struct PreviewZoomActions {
        let perform: (MacZoomStep) -> Void

        public func zoomIn() {
            perform(.zoomIn)
        }

        public func zoomOut() {
            perform(.zoomOut)
        }

        public func zoomToFit() {
            perform(.fit)
        }
    }

    public extension FocusedValues {
        @Entry var previewZoom: PreviewZoomActions?
    }

    /// Gives a zoomable preview keyboard zoom (the View menu items) and VoiceOver's zoom action,
    /// so zooming never needs a trackpad pinch or a double click.
    struct MacPreviewZoom: ViewModifier {
        @State private var controller = MacZoomController()

        func body(content: Content) -> some View {
            content
                .environment(\.macZoomController, controller)
                .focusedSceneValue(\.previewZoom, PreviewZoomActions { controller.zoom($0) })
                .accessibilityZoomAction { action in
                    controller.zoom(action.direction == .zoomIn ? .zoomIn : .zoomOut)
                }
        }
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
            attachController(context.environment.macZoomController, to: scrollView, coordinator: context.coordinator)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            context.coordinator.onZoomChange = onZoomChange
            context.coordinator.hostingView.rootView = content
            attachController(context.environment.macZoomController, to: scrollView, coordinator: context.coordinator)
        }

        private func attachController(_ controller: MacZoomController?, to scrollView: NSScrollView, coordinator: Coordinator) {
            controller?.attach { [weak coordinator, weak scrollView] step in
                guard let coordinator, let scrollView else { return }
                coordinator.zoom(step, in: scrollView)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(hostingView: NSHostingView(rootView: content), onZoomChange: onZoomChange)
        }

        static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
            coordinator.stopObserving()
        }

        @MainActor
        final class Coordinator: NSObject {
            let hostingView: NSHostingView<Content>
            var onZoomChange: (Bool) -> Void
            private var isLastReportedZoomed = false
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

            /// A block observer stays registered (and retained) until removed, so the preview that
            /// closes takes it down with it.
            func stopObserving() {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                observer = nil
            }

            /// A menu or VoiceOver zoom step, centered on what is on screen; instant under Reduce Motion.
            func zoom(_ step: MacZoomStep, in scrollView: NSScrollView) {
                let target = switch step {
                case .zoomIn: min(scrollView.magnification * Constants.zoomStepFactor, scrollView.maxMagnification)
                case .zoomOut: max(scrollView.magnification / Constants.zoomStepFactor, scrollView.minMagnification)
                case .fit: scrollView.minMagnification
                }
                let visible = scrollView.contentView.bounds
                let center = NSPoint(x: visible.midX, y: visible.midY)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    scrollView.setMagnification(target, centeredAt: center)
                } else {
                    scrollView.animator().setMagnification(target, centeredAt: center)
                }
                reportZoom(of: scrollView, target: target)
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
                guard isZoomed != isLastReportedZoomed else { return }
                isLastReportedZoomed = isZoomed
                onZoomChange(isZoomed)
            }
        }
    }

    #Preview {
        ZoomableScrollView {
            LinearGradient(colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .previewCanvas(.window)
        }
        .previewCanvas(.dialog)
    }
#endif
