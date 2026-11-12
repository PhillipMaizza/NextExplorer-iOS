#if os(iOS)
    import SwiftUI
    import UIKit

    /// The gallery's page dots as a native `UIPageControl`: it windows a long folder of images into a
    /// few sliding dots on its own, and tapping or scrubbing it moves the pager. Drawn by the gallery
    /// inside the safe area, above its bottom bar, instead of the `TabView` page style's dots, which
    /// sit on the home indicator once the pager ignores the safe area.
    struct GalleryPageControl: UIViewRepresentable {
        let numberOfPages: Int
        @Binding var currentPage: Int

        func makeCoordinator() -> Coordinator {
            Coordinator(currentPage: $currentPage)
        }

        func makeUIView(context: Context) -> UIPageControl {
            let control = UIPageControl()
            control.backgroundStyle = .prominent
            control.hidesForSinglePage = true
            control.addTarget(context.coordinator, action: #selector(Coordinator.pageChanged(_:)), for: .valueChanged)
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .vertical)
            return control
        }

        func updateUIView(_ control: UIPageControl, context: Context) {
            context.coordinator.currentPage = $currentPage
            control.numberOfPages = numberOfPages
            control.currentPage = currentPage
        }

        final class Coordinator: NSObject {
            var currentPage: Binding<Int>

            init(currentPage: Binding<Int>) {
                self.currentPage = currentPage
            }

            @MainActor @objc func pageChanged(_ control: UIPageControl) {
                currentPage.wrappedValue = control.currentPage
            }
        }
    }

    #Preview("Few pages") {
        @Previewable @State var page = 1
        GalleryPageControl(numberOfPages: 4, currentPage: $page)
            .padding()
            .background(Color.black)
    }

    #Preview("Many pages") {
        @Previewable @State var page = 40
        GalleryPageControl(numberOfPages: 120, currentPage: $page)
            .padding()
            .background(Color.black)
    }

    #Preview("Single page hides") {
        @Previewable @State var page = 0
        GalleryPageControl(numberOfPages: 1, currentPage: $page)
            .padding()
            .background(Color.black)
    }
#endif
