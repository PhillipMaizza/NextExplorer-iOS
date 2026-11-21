#if os(iOS)
    import DesignSystem
    import Localization
    import PDFKit
    import SwiftUI

    private enum Constants {
        /// How long the page pill stays after the page changes.
        static let pillDuration: Duration = .seconds(1.5)
    }

    /// A PDF in the gallery: PDFKit in process, pages with
    /// shadows and gaps on a grey backdrop, the first page below the frosted bar with the rest
    /// scrolling under it, and a "1 of 3" pill when the page changes. Quick Look would draw it out
    /// of process and take every swipe, so the gallery could not page past it. The document is
    /// parsed off the main thread.
    struct PDFGalleryPage: View {
        let fileURL: URL
        /// The space the bars take, for placing the page pill below the title.
        var contentInsets = EdgeInsets()

        @State private var phase = Phase.loading
        @State private var pill: PageCount?

        private enum Phase {
            case loading
            case loaded(PDFDocumentBox)
            /// Password protected: PDFKit would draw it blank, Quick Look asks for the password.
            case locked
            case failed
        }

        private struct PageCount: Equatable {
            let page: Int
            let count: Int
        }

        var body: some View {
            Group {
                switch phase {
                case .loading:
                    DSSpinner()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(box):
                    PDFDocumentView(
                        document: box.document,
                        onPageChange: { page, count in
                            withAnimation(DSMotion.galleryFade) {
                                pill = PageCount(page: page, count: count)
                            }
                        }
                    )
                case .locked:
                    QuickLookPreview(url: fileURL)
                case .failed:
                    PreviewErrorView(message: L10n.EmptyState.loadFailed)
                }
            }
            .overlay(alignment: .topLeading) { pageLabel }
            .background(Color(uiColor: .secondarySystemBackground))
            .task(id: fileURL) {
                let url = fileURL
                let parsed = await Task.detached(priority: .userInitiated) {
                    PDFDocument(url: url).map(PDFDocumentBox.init)
                }.value
                if !Task.isCancelled {
                    phase = parsed.map { $0.document.isLocked ? .locked : .loaded($0) } ?? .failed
                }
            }
            // Each page change restarts the countdown; a newer one cancels the older.
            .task(id: pill) {
                guard pill != nil else { return }
                try? await DSMotion.waitForStep(Constants.pillDuration)
                guard !Task.isCancelled else { return }
                withAnimation(DSMotion.galleryFade) {
                    pill = nil
                }
            }
        }

        @ViewBuilder
        private var pageLabel: some View {
            if let pill, pill.count > 1 {
                Text(L10n.PdfPreview.pageIndicator(pill.page, pill.count))
                    .type(.body2(.regular), style: .secondary)
                    .padding(.horizontal, .space12)
                    .padding(.vertical, .space4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, contentInsets.top + .space8)
                    .padding(.leading, .space16)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Carries a parsed document from the parsing task to the view; it is only read on the main
    /// actor once handed over.
    struct PDFDocumentBox: @unchecked Sendable {
        let document: PDFDocument
    }

    /// PDFKit in a view controller, whose safe area already holds the bars' space: PDFKit lays the
    /// first page out below it and scrolls the rest under it on its own.
    private struct PDFDocumentView: UIViewControllerRepresentable {
        let document: PDFDocument
        let onPageChange: (Int, Int) -> Void

        func makeUIViewController(context: Context) -> PDFHostController {
            let controller = PDFHostController()
            controller.pdfView.document = document
            context.coordinator.observe(controller.pdfView)
            return controller
        }

        func updateUIViewController(_ controller: PDFHostController, context: Context) {
            context.coordinator.onPageChange = onPageChange
            if controller.pdfView.document !== document {
                controller.pdfView.document = document
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onPageChange: onPageChange)
        }

        @MainActor
        final class Coordinator: NSObject {
            var onPageChange: (Int, Int) -> Void

            init(onPageChange: @escaping (Int, Int) -> Void) {
                self.onPageChange = onPageChange
            }

            func observe(_ view: PDFView) {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(pageChanged(_:)),
                    name: .PDFViewPageChanged,
                    object: view
                )
            }

            @objc private func pageChanged(_ notification: Notification) {
                guard let view = notification.object as? PDFView,
                      let document = view.document,
                      let page = view.currentPage else { return }
                onPageChange(document.index(for: page) + 1, document.pageCount)
            }
        }
    }

    final class PDFHostController: UIViewController {
        let pdfView = PDFView()
        private var hasPlacedFirstPage = false

        /// PDFKit's own scroll view: its insets follow this controller's safe area.
        private var scrollView: UIScrollView? {
            pdfView.subviews.lazy.compactMap { $0 as? UIScrollView }.first
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let scrollView, pdfView.document != nil else { return }
            let insets = UIEdgeInsets(
                top: view.safeAreaInsets.top,
                left: 0,
                bottom: view.safeAreaInsets.bottom,
                right: 0
            )
            if scrollView.contentInsetAdjustmentBehavior == .never, scrollView.contentInset != insets {
                scrollView.contentInset = insets
                scrollView.verticalScrollIndicatorInsets = insets
            }
            // The first page opens just below the bar; after that the reader scrolls.
            if !hasPlacedFirstPage, scrollView.contentSize.height > 0 {
                hasPlacedFirstPage = true
                scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
            }
        }

        override func loadView() {
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.autoScales = true
            pdfView.displaysPageBreaks = true
            pdfView.pageShadowsEnabled = true
            pdfView.backgroundColor = .secondarySystemBackground
            view = pdfView
        }
    }

    #Preview("Unreadable file") {
        PDFGalleryPage(fileURL: URL(fileURLWithPath: "/missing.pdf"))
    }
#endif
