import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    /// Vertical drag distance past which releasing dismisses the gallery.
    static let dismissDistanceThreshold: CGFloat = 120
    /// Projected fling distance that dismisses even on a short, fast flick.
    static let dismissPredictedThreshold: CGFloat = 360
    /// Only start tracking a drag as a dismiss once it's clearly more vertical than
    /// horizontal — horizontal drags belong to the `TabView`'s own paging.
    static let dragMinimumDistance: CGFloat = 12
    /// Floor for how far the content dims/shrinks while dragging.
    static let minBackgroundOpacity: Double = 0.35
    static let dragScaleFloor: CGFloat = 0.88
    static let dragScaleDivisor: CGFloat = 1400
    static let dragResetSpringResponse: Double = 0.3
    static let dragResetSpringDamping: Double = 0.85
    /// Fade the frozen content + dimmed backdrop to nothing on release-to-dismiss, then pull
    /// the cover with animations off — so the exit is a clean crossfade, not our motion
    /// fighting the fullScreenCover's own slide-from-bottom.
    static let dismissFadeDuration: Double = 0.2
    /// Content opacity at full drag progress (before release) — a slight fade under the
    /// finger on top of the shrink.
    static let draggingContentOpacityFloor: Double = 0.6
    /// Chrome (nav bar + bottom bar + status bar + page dots) crossfade on tap. Short, to
    /// match the Photos viewer.
    static let controlsFadeDuration: Double = 0.22
}

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

    private var dragProgress: CGFloat {
        min(1, abs(dragOffset) / Constants.dismissDistanceThreshold)
    }

    private var backgroundOpacity: Double {
        if isDismissing { return 0 }
        return 1 - (1 - Constants.minBackgroundOpacity) * Double(dragProgress)
    }

    private var contentOpacity: Double {
        if isDismissing { return 0 }
        return 1 - (1 - Constants.draggingContentOpacityFloor) * Double(dragProgress)
    }

    private var dragScale: CGFloat {
        max(Constants.dragScaleFloor, 1 - abs(dragOffset) / Constants.dragScaleDivisor)
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
        DragGesture(minimumDistance: Constants.dragMinimumDistance)
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
                let passedDistance = abs(value.translation.height) > Constants.dismissDistanceThreshold
                let passedFlick = abs(value.predictedEndTranslation.height) > Constants.dismissPredictedThreshold
                if passedDistance || passedFlick {
                    // Freeze the content where the finger left it and crossfade it out, then
                    // remove the cover with animations off — no fly-out to collide with the
                    // fullScreenCover's own slide.
                    withAnimation(.easeOut(duration: Constants.dismissFadeDuration)) {
                        isDismissing = true
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onDismiss() }
                    }
                } else {
                    withAnimation(.spring(
                        response: Constants.dragResetSpringResponse,
                        dampingFraction: Constants.dragResetSpringDamping
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

    @State private var fileURL: URL?
    @State private var errorMessage: String?
    @Dependency(\.filesClient) private var filesClient

    var body: some View {
        ZStack {
            if let fileURL {
                // GIFs play their real animation via `AnimatedImageView` — `AsyncImage` only
                // ever shows a GIF's first frame, no animation at all.
                if item.kind.lowercased() == "gif" {
                    ZoomableScrollView(onZoomChange: onZoomChange) { AnimatedImageView(fileURL: fileURL) }
                } else {
                    AsyncImage(url: fileURL) { phase in
                        switch phase {
                        case let .success(image):
                            ZoomableScrollView(onZoomChange: onZoomChange) { image.resizable().scaledToFit() }
                        case .failure:
                            statusContent(message: L10n.Gallery.loadFailed)
                        default:
                            ProgressView()
                        }
                    }
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
                fileURL = try await filesClient.previewFile(serverURL, item)
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
