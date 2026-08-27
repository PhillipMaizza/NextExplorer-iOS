import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    static let toolbarSpacing: CGFloat = .space16
    static let toolbarHorizontalPadding: CGFloat = .space16
    static let toolbarVerticalPadding: CGFloat = .space12
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
    /// Lifts the `TabView` page dots clear of the bottom-trailing action bar — without it the
    /// dots sit in the same band as the toolbar and collide.
    static let pageIndicatorBottomInset: CGFloat = 52
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
    private let onDownload: ((FileItem) -> Void)?
    private let onDelete: ((FileItem) -> Void)?

    @State private var selection: String
    /// Live vertical translation of an in-progress dismiss drag (0 when idle). Drives the
    /// content offset plus the background dim/shrink, matching the iOS Photos swipe-to-close.
    @State private var dragOffset: CGFloat = 0
    /// Set once a drag crosses the dismiss threshold: fades content + background to 0 while
    /// it flies off, so the fullScreenCover's own slide-out is never seen.
    @State private var isDismissing = false

    init(
        items: [FileItem],
        initialItem: FileItem,
        serverURL: URL,
        onDismiss: @escaping () -> Void,
        onShare: ((FileItem) -> Void)? = nil,
        onDownload: ((FileItem) -> Void)? = nil,
        onDelete: ((FileItem) -> Void)? = nil
    ) {
        self.items = items
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self.onShare = onShare
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
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                TabView(selection: $selection) {
                    ForEach(items) { item in
                        ImageGalleryPage(item: item, serverURL: serverURL)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
                .padding(.bottom, items.count > 1 ? Constants.pageIndicatorBottomInset : 0)
            }
            .scaleEffect(dragScale)
            .offset(y: dragOffset)
            .opacity(contentOpacity)
            .overlay(alignment: .bottomTrailing) {
                actionBar
                    .padding(.horizontal, Constants.toolbarHorizontalPadding)
                    .padding(.bottom, Constants.toolbarHorizontalPadding)
            }
        }
        .simultaneousGesture(dismissDrag)
        .onAppear { OrientationLock.shared.unlock() }
        .onDisappear { OrientationLock.shared.lock() }
    }

    /// Vertical swipe (either direction) to dismiss, like the iOS Photos viewer — runs
    /// alongside the `TabView`'s horizontal paging, which keeps its own horizontal drags.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: Constants.dragMinimumDistance)
            .onChanged { value in
                guard !isDismissing, abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
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

    private var topBar: some View {
        HStack(spacing: Constants.toolbarSpacing) {
            // Fixed white, not `Color.primaryDS` — unlike the close button (which gets a
            // frosted material chip that adapts on its own), this label sits directly on the
            // always-black gallery background, so a theme-adaptive color would go
            // near-invisible in light mode.
            Text(currentName)
                .type(.body1(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            DSCloseButton(action: onDismiss)
        }
        .padding(.horizontal, Constants.toolbarHorizontalPadding)
        .padding(.vertical, Constants.toolbarVerticalPadding)
    }

    @ViewBuilder
    private var actionBar: some View {
        PreviewActionBar {
            if let currentItem {
                SystemShareButton(item: currentItem, serverURL: serverURL, tint: .white)
            }
            if let onShare {
                PreviewChipButton(icon: IconKit.shareLink, tint: .white) { currentItem.map(onShare) }
            }
            if let onDownload {
                PreviewChipButton(icon: IconKit.download, tint: .white) { currentItem.map(onDownload) }
            }
            if let onDelete {
                PreviewChipButton(icon: IconKit.delete, tint: .negative) { currentItem.map(onDelete) }
            }
        }
    }
}

private struct ImageGalleryPage: View {
    let item: FileItem
    let serverURL: URL

    @State private var fileURL: URL?
    @State private var errorMessage: String?
    @Dependency(\.filesClient) private var filesClient

    var body: some View {
        ZStack {
            if let fileURL {
                // GIFs play their real animation via `AnimatedImageView` — `AsyncImage` only
                // ever shows a GIF's first frame, no animation at all.
                if item.kind.lowercased() == "gif" {
                    AnimatedImageView(fileURL: fileURL)
                } else {
                    AsyncImage(url: fileURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFit()
                        case .failure:
                            statusContent(message: "Couldn't load this image.")
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
                errorMessage = (error as? FilesClientError)?.userMessage ?? "Couldn't load this image."
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
