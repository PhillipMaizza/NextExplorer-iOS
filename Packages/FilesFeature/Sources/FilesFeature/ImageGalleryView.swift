import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
import UIKit

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    /// Chrome (nav bar + bottom bar + status bar + page dots) crossfade on tap. Short, to
    /// match the Photos viewer.
    static let controlsFadeDuration: Double = 0.22
}

/// Swipe-to-dismiss thresholds + offset math, shared with the other full-screen viewers.
private typealias DismissMetrics = SwipeToDismissMetrics

/// Swipeable full-screen viewer for every image/RAW photo in the current folder, not just the
/// one tapped — mirrors browsing a real photo gallery instead of dismissing back to the list
/// between each image. Every page reuses `FilesClient.previewFile`'s on-disk cache (see
/// `FilesService.previewFile`), so revisiting an already-viewed image in the same session
/// never re-hits the server.
struct ImageGalleryView: View {
    let items: [FileItem]
    let serverURL: URL
    let onDismiss: () -> Void
    /// Toolbar actions on the current image — routed back to `BrowseFeature` by the caller.
    /// `nil` hides the button (e.g. no delete permission).
    private let onShare: ((FileItem) -> Void)?
    private let onRename: ((FileItem) -> Void)?
    private let onDownload: ((FileItem) -> Void)?
    private let onDelete: ((FileItem) -> Void)?

    @State private var selection: String
    /// Live vertical translation of an in-progress dismiss drag (0 when idle). Drives the
    /// content offset plus the background dim/shrink, matching the iOS Photos swipe-to-close.
    @State private var dragOffset: CGFloat = 0
    /// Set once a drag crosses the dismiss threshold: fades content + background to 0 while
    /// it flies off, so the fullScreenCover's own slide-out is never seen.
    @State private var isDismissing = false
    /// Single-tap toggles the nav bar + bottom action bar + system overlays, like the Photos
    /// app's full-screen viewer.
    @State private var areControlsHidden = false
    /// True while the current page's image is magnified — suspends swipe-to-dismiss so
    /// panning a zoomed image doesn't close the gallery. Reset on every page change.
    @State private var isZoomed = false

    init(
        items: [FileItem],
        initialItem: FileItem,
        serverURL: URL,
        onDismiss: @escaping () -> Void,
        onShare: ((FileItem) -> Void)? = nil,
        onRename: ((FileItem) -> Void)? = nil,
        onDownload: ((FileItem) -> Void)? = nil,
        onDelete: ((FileItem) -> Void)? = nil
    ) {
        self.items = items
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        self._selection = State(initialValue: initialItem.id)
    }

    private var currentItem: FileItem? {
        items.first { $0.id == selection }
    }

    private var currentName: String {
        currentItem?.name ?? ""
    }

    private var backgroundOpacity: Double {
        DismissMetrics.backgroundOpacity(forOffset: dragOffset, isDismissing: isDismissing)
    }

    private var contentOpacity: Double {
        DismissMetrics.contentOpacity(forOffset: dragOffset, isDismissing: isDismissing)
    }

    private var dragScale: CGFloat {
        DismissMetrics.scale(forOffset: dragOffset)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                // Full-bleed on every edge: the bars float over the image, so toggling them
                // never resizes or reflows the content — the image stays perfectly still
                // while the chrome fades, matching the Photos viewer.
                TabView(selection: $selection) {
                    ForEach(items) { item in
                        ImageGalleryPage(item: item, serverURL: serverURL, onZoomChange: { isZoomed = $0 })
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 && !areControlsHidden ? .always : .never))
                .ignoresSafeArea()
                .scaleEffect(dragScale)
                .offset(y: dragOffset)
                .opacity(contentOpacity)
            }
            .onChange(of: selection) { _, _ in isZoomed = false }
            .contentShape(Rectangle())
            // A short fade, nothing more. The earlier lag was this animation fighting the
            // content reflow when the bars resized the image — now that the image is
            // full-bleed and never moves, only the chrome itself crossfades.
            .onTapGesture {
                withAnimation(.easeInOut(duration: Constants.controlsFadeDuration)) {
                    areControlsHidden.toggle()
                }
            }
            .simultaneousGesture(dismissDrag)
            .previewChrome(
                title: currentName,
                systemShare: currentItem.map { .remote($0, serverURL: serverURL) } ?? .unavailable,
                onShareLink: currentItemAction(onShare),
                onRename: currentItemAction(onRename),
                onDownload: currentItemAction(onDownload),
                onDelete: currentItemAction(onDelete),
                onClose: onDismiss
            )
            .toolbar(areControlsHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar(areControlsHidden ? .hidden : .visible, for: .bottomBar)
            .statusBarHidden(areControlsHidden)
        }
        .onAppear { OrientationLock.shared.unlock() }
        .onDisappear { OrientationLock.shared.lock() }
    }

    /// Binds one of the caller's `(FileItem) -> Void` toolbar callbacks to whichever image is
    /// currently on screen, or `nil` when the caller didn't supply that action.
    private func currentItemAction(_ action: ((FileItem) -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return { currentItem.map(action) }
    }

    /// Vertical swipe (either direction) to dismiss, like the iOS Photos viewer — runs
    /// alongside the `TabView`'s horizontal paging, which keeps its own horizontal drags.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: DismissMetrics.minimumDragDistance)
            .onChanged { value in
                guard !isZoomed, !isDismissing, abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed, abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                if DismissMetrics.shouldDismiss(
                    translationHeight: value.translation.height,
                    predictedHeight: value.predictedEndTranslation.height
                ) {
                    // Freeze the content where the finger left it and crossfade it out, then
                    // remove the cover with animations off — no fly-out to collide with the
                    // fullScreenCover's own slide.
                    withAnimation(.easeOut(duration: DismissMetrics.dismissFadeDuration)) {
                        isDismissing = true
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onDismiss() }
                    }
                } else {
                    withAnimation(.spring(
                        response: DismissMetrics.resetSpringResponse,
                        dampingFraction: DismissMetrics.resetSpringDamping
                    )) {
                        dragOffset = 0
                    }
                }
            }
    }

}

private struct ImageGalleryPage: View {
    let item: FileItem
    let serverURL: URL
    var onZoomChange: (Bool) -> Void = { _ in }

    @State private var gifURL: URL?
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @Dependency(\.filesClient) private var filesClient

    /// Decode ceiling for a still image. Generous enough that `ZoomableScrollView`'s 4x zoom
    /// still looks sharp, without ever holding a full 48MP bitmap resident. Read from
    /// `UIScreen` on the main actor inside `.task`, not a nonisolated static.
    @MainActor private var maxPixelDimension: CGFloat {
        let screen = UIScreen.main.bounds
        return max(screen.width, screen.height) * UIScreen.main.scale * 2
    }

    var body: some View {
        ZStack {
            if let gifURL {
                // GIFs play their real animation via `AnimatedImageView` — a decoded still
                // would only ever show the first frame.
                ZoomableScrollView(onZoomChange: onZoomChange) { AnimatedImageView(fileURL: gifURL) }
            } else if let image {
                ZoomableScrollView(onZoomChange: onZoomChange) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else if let errorMessage {
                statusContent(message: errorMessage)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            do {
                let fileURL = try await filesClient.previewFile(serverURL, item)
                if item.kind.lowercased() == "gif" {
                    gifURL = fileURL
                } else {
                    let target = maxPixelDimension
                    let decoded = await Task.detached(priority: .userInitiated) {
                        ImageDownsampling.image(from: fileURL, maxPixelDimension: target)
                    }.value
                    guard let decoded else {
                        errorMessage = L10n.Gallery.loadFailed
                        return
                    }
                    image = decoded
                }
            } catch {
                errorMessage = (error as? FilesClientError)?.userMessage ?? L10n.Gallery.loadFailed
            }
        }
    }

    private func statusContent(message: String) -> some View {
        VStack(spacing: Constants.statusSpacing) {
            IconKit.warning
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.negative)
                .frame(width: .iconMedium, height: .iconMedium)
            Text(message).type(.body1(.regular), style: .secondary)
        }
    }
}

#Preview("Single image") {
    ImageGalleryView(
        items: [FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")],
        initialItem: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        onDismiss: {}
    )
}
