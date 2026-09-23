import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
#if os(iOS)
    import UIKit
#endif

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    /// Chrome (nav bar + bottom bar + status bar + page dots) crossfade on tap. Short, to
    /// match the Photos viewer.
    static let controlsFadeDuration: Double = 0.22
    /// How many pages either side of the current one keep a decoded bitmap resident. A page
    /// style `TabView` materializes every child, so without this a folder of hundreds of photos
    /// would hold a decoded image per page and jetsam. Pages outside the window drop their
    /// bitmap and re decode when swiped back near.
    static let retainWindow = 2
    /// Blur applied to the low quality thumbnail placeholder so its upscaling reads as a soft
    /// preview behind the sharpening image rather than a pixelated still.
    static let placeholderBlur: CGFloat = 18
    /// The image settles from this scale to 1 when it finishes loading, for a subtle finish pop.
    static let settleFromScale: CGFloat = 1.03
    static let settleSpringResponse: Double = 0.35
    static let settleSpringDamping: Double = 0.82
    /// Crossfade when the first frame replaces the placeholder.
    static let imageFadeDuration: Double = 0.2
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
    /// Reports the page currently on screen as the user swipes, so the caller can keep the
    /// `.zoom` transition source (and the underlying list's scroll position) on the image the
    /// cover will actually dismiss back to, not the one first tapped.
    private let onCurrentItemChange: (FileItem) -> Void

    @State private var selection: String
    /// Single-tap toggles the nav bar + bottom action bar + system overlays, like the Photos
    /// app's full-screen viewer.
    @State private var areControlsHidden = false
    init(
        items: [FileItem],
        initialItem: FileItem,
        serverURL: URL,
        onDismiss: @escaping () -> Void,
        onShare: ((FileItem) -> Void)? = nil,
        onRename: ((FileItem) -> Void)? = nil,
        onDownload: ((FileItem) -> Void)? = nil,
        onDelete: ((FileItem) -> Void)? = nil,
        onCurrentItemChange: @escaping (FileItem) -> Void = { _ in }
    ) {
        self.items = items
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self.onShare = onShare
        self.onRename = onRename
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCurrentItemChange = onCurrentItemChange
        _selection = State(initialValue: initialItem.id)
    }

    private var currentItem: FileItem? {
        items.first { $0.id == selection }
    }

    private var currentName: String {
        currentItem?.name ?? ""
    }

    #if os(macOS)
        /// A Mac has no swipe pager: the current image fills the window and the arrow keys step
        /// through the set.
        private var pager: some View {
            Group {
                if let index = items.firstIndex(where: { $0.id == selection }) {
                    ImageGalleryPage(item: items[index], serverURL: serverURL, isNear: true)
                        .id(items[index].id)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { step(by: -1) }
            .onKeyPress(.rightArrow) { step(by: 1) }
        }

        private func step(by offset: Int) -> KeyPress.Result {
            guard let index = items.firstIndex(where: { $0.id == selection }),
                  items.indices.contains(index + offset) else { return .ignored }
            selection = items[index + offset].id
            return .handled
        }
    #else
        private var pager: some View {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ImageGalleryPage(item: item, serverURL: serverURL, isNear: isNear(index))
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 && !areControlsHidden ? .always : .never))
        }
    #endif

    var body: some View {
        NavigationStack {
            // Full-bleed on every edge: the bars float over the image, so toggling them
            // never resizes or reflows the content — the image stays perfectly still
            // while the chrome fades, matching the Photos viewer.
            pager
                .ignoresSafeArea()
                // A rename changes the current image's id (it's path-derived); deleting one drops
                // it. Close if that emptied the gallery, otherwise hold the same slot so a dangling
                // `selection` lands on the neighbour.
                .onChange(of: items) { oldItems, newItems in
                    if newItems.isEmpty {
                        onDismiss(); return
                    }
                    guard !newItems.contains(where: { $0.id == selection }) else { return }
                    let slot = oldItems.firstIndex { $0.id == selection } ?? 0
                    selection = (newItems.indices.contains(slot) ? newItems[slot] : newItems[newItems.count - 1]).id
                }
                // Keep the caller's zoom source and list scroll aligned with the page swiped to.
                .onChange(of: selection) { _, _ in currentItem.map(onCurrentItemChange) }
                .contentShape(Rectangle())
                // A short fade, nothing more. The earlier lag was this animation fighting the
                // content reflow when the bars resized the image — now that the image is
                // full-bleed and never moves, only the chrome itself crossfades.
                .onTapGesture {
                    withAnimation(.easeInOut(duration: Constants.controlsFadeDuration)) {
                        areControlsHidden.toggle()
                    }
                }
                .previewChrome(
                    title: currentName,
                    systemShare: currentItem.map { .remote($0, serverURL: serverURL) } ?? .unavailable,
                    onShareLink: currentItemAction(onShare),
                    onRename: currentItemAction(onRename),
                    onDownload: currentItemAction(onDownload),
                    onDelete: currentItemAction(onDelete),
                    onClose: onDismiss
                )
                .hidesNavigationBar(areControlsHidden)
                .hidesBottomBar(areControlsHidden)
                .statusBarHidden(areControlsHidden)
        }
        .onAppear { OrientationLock.shared.unlock() }
        .onDisappear { OrientationLock.shared.lock() }
    }

    /// Whether page `index` is close enough to the current selection to keep a decoded bitmap.
    private func isNear(_ index: Int) -> Bool {
        guard let selected = items.firstIndex(where: { $0.id == selection }) else { return false }
        return abs(index - selected) <= Constants.retainWindow
    }

    /// Binds one of the caller's `(FileItem) -> Void` toolbar callbacks to whichever image is
    /// currently on screen, or `nil` when the caller didn't supply that action.
    private func currentItemAction(_ action: ((FileItem) -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return { currentItem.map(action) }
    }
}

/// The image page lifecycle as one value (rule 8): `loading`, a progressive `streaming` frame, the
/// final `loaded` image, a `gif`, or a `failed` message. Not `Equatable` because `UIImage` isn't;
/// the view animates off the derived `hasImage` / `isFinal` instead.
private enum GalleryImagePhase {
    case loading
    case streaming(PlatformImage)
    case loaded(PlatformImage)
    case gif(URL)
    case failed(String)

    var displayImage: PlatformImage? {
        switch self {
        case let .streaming(image), let .loaded(image): image
        default: nil
        }
    }

    var hasImage: Bool {
        displayImage != nil
    }

    var isFinal: Bool {
        if case .loaded = self {
            true
        } else {
            false
        }
    }
}

private struct ImageGalleryPage: View {
    let item: FileItem
    let serverURL: URL
    /// When false (page is outside the retain window) the decoded bitmap is dropped so a large
    /// folder can't hold an image per page. Flips back true when swiped near, triggering a
    /// re decode.
    var isNear: Bool = true
    var onZoomChange: (Bool) -> Void = { _ in }

    /// One lifecycle for the page, not a spread of `image` + `gifURL` + `errorMessage` +
    /// `didFinishLoading` bools (rule 8). `streaming` is a progressive frame still sharpening,
    /// `loaded` is the final full quality image, which is what drives the settle animation.
    @State private var phase: GalleryImagePhase = .loading
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.offlineFileStore) private var offlineFileStore

    /// Decode ceiling for a still image. Generous enough that `ZoomableScrollView`'s 4x zoom
    /// still looks sharp, without ever holding a full 48MP bitmap resident. Read from
    /// `UIScreen` on the main actor inside `.task`, not a nonisolated static.
    @MainActor private var maxPixelDimension: CGFloat {
        let screen = PlatformScreen.bounds
        return max(screen.width, screen.height) * PlatformScreen.scale * 2
    }

    /// The blurred thumbnail placeholder shows only before any frame has decoded, so a page never
    /// blanks to a spinner. Once even a rough streaming frame is up, it covers the placeholder.
    private var showsPlaceholder: Bool {
        guard item.supportsThumbnail else { return false }
        if case .loading = phase {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            if showsPlaceholder {
                ThumbnailImage(
                    serverURL: serverURL, path: item.id, signature: item.cacheSignature,
                    fallbackIcon: IconKit.document, iconTint: Color.secondaryDS
                )
                .blur(radius: Constants.placeholderBlur)
                .clipped()
                .allowsHitTesting(false)
            }

            switch phase {
            case let .gif(url):
                // GIFs play their real animation via `AnimatedImageView` — a decoded still would
                // only ever show the first frame.
                ZoomableScrollView(onZoomChange: onZoomChange) { AnimatedImageView(fileURL: url) }
            case let .streaming(uiImage), let .loaded(uiImage):
                ZoomableScrollView(onZoomChange: onZoomChange) {
                    Image(platformImage: uiImage).resizable().scaledToFit()
                }
                .transition(.opacity)
                // Settle from a slight scale to 1 the moment the final image lands.
                .scaleEffect(phase.isFinal ? 1 : Constants.settleFromScale)
                .animation(.spring(response: Constants.settleSpringResponse, dampingFraction: Constants.settleSpringDamping), value: phase.isFinal)
            case let .failed(message):
                statusContent(message: message)
            case .loading:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: Constants.imageFadeDuration), value: phase.hasImage)
        .task(id: "\(item.id)\u{0}\(isNear)") { await load() }
    }

    @MainActor
    private func load() async {
        guard isNear else {
            // Outside the retain window: release the decoded bitmap (and any GIF handle) so it
            // stops counting against resident memory.
            phase = .loading
            return
        }
        // Only load from a clean slate; a page already loaded (or mid stream) is left as is.
        guard case .loading = phase else { return }

        // GIFs animate from a file (offline/cache aware); a decoded still would freeze on frame one.
        if item.kind.lowercased() == "gif" {
            do {
                let fileURL = try await filesClient.previewFile(serverURL, item)
                if !Task.isCancelled {
                    phase = .gif(fileURL)
                }
            } catch {
                if !Task.isCancelled {
                    phase = .failed((error as? FilesClientError)?.userMessage ?? L10n.Gallery.loadFailed)
                }
            }
            return
        }

        let target = maxPixelDimension

        // A pinned offline copy decodes locally at final quality with no network.
        if let localURL = offlineFileStore.localURL(item) {
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDownsampling.image(from: localURL, maxPixelDimension: target)
            }.value
            if Task.isCancelled {
                return
            }
            phase = decoded.map(GalleryImagePhase.loaded) ?? .failed(L10n.Gallery.loadFailed)
            return
        }

        // Online: stream progressively so the image ramps from rough to sharp with no spinner.
        guard let url = FilesClient.previewURL(serverURL: serverURL, item: item) else {
            await decodeViaPreviewFile(target: target)
            return
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        var lastFrame: PlatformImage?
        for await frame in ProgressiveImageLoader.frames(url: url, cookies: cookies, maxPixelDimension: target) {
            if Task.isCancelled {
                return
            }
            lastFrame = frame
            phase = .streaming(frame)
        }
        if Task.isCancelled {
            return
        }
        if let lastFrame {
            // The last frame is the full quality one: settle it in.
            phase = .loaded(lastFrame)
            return
        }
        // Nothing decoded (a server error, not a cancellation): fall back to a plain download so a
        // real failure surfaces its message instead of a silent blank behind the placeholder.
        await decodeViaPreviewFile(target: target)
    }

    @MainActor
    private func decodeViaPreviewFile(target: CGFloat) async {
        do {
            let fileURL = try await filesClient.previewFile(serverURL, item)
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDownsampling.image(from: fileURL, maxPixelDimension: target)
            }.value
            if Task.isCancelled {
                return
            }
            phase = decoded.map(GalleryImagePhase.loaded) ?? .failed(L10n.Gallery.loadFailed)
        } catch {
            if !Task.isCancelled {
                phase = .failed((error as? FilesClientError)?.userMessage ?? L10n.Gallery.loadFailed)
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
