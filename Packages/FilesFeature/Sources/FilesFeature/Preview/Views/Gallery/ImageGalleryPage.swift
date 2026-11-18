import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import NetworkClient
import SwiftUI

private enum Constants {
    /// Blur applied to the low quality thumbnail placeholder so its upscaling reads as a soft
    /// preview behind the sharpening image rather than a pixelated still.
    static let placeholderBlur: CGFloat = 18
    /// The image settles from this scale to 1 when it finishes loading, for a subtle finish pop.
    static let settleFromScale: CGFloat = 1.03
}

/// The image page lifecycle as one value, so no two states can be set at once: `loading`, a progressive `streaming`
/// frame, the
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

struct ImageGalleryPage: View {
    let item: FileItem
    let serverURL: URL
    /// When false (page is outside the retain window) the decoded bitmap is dropped so a large
    /// folder can't hold an image per page. Flips back true when swiped near, triggering a
    /// re decode.
    var isNear: Bool = true
    var onZoomChange: (Bool) -> Void = { _ in }

    /// One lifecycle for the page, not a spread of `image` + `gifURL` + `errorMessage` +
    /// `didFinishLoading` bools that could disagree. `streaming` is a progressive frame still sharpening,
    /// `loaded` is the final full quality image, which is what drives the settle animation.
    @State private var phase: GalleryImagePhase = .loading
    /// The date and size the shown image was loaded for, so a file replaced on the server loads again.
    @State private var loadedSignature: String?
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.offlineFileStore) private var offlineFileStore
    @Dependency(\.connectivity) private var connectivity

    @Environment(\.displayScale) private var displayScale

    /// Decode ceiling for a still image. Generous enough that `ZoomableScrollView`'s 4x zoom
    /// still looks sharp, without ever holding a full 48MP bitmap resident. Sized off the
    /// window the app is in, which on iPhone Duo is whichever panel is showing.
    @MainActor private var maxPixelDimension: CGFloat {
        let bounds = PlatformScreen.bounds
        return Self.decodeTarget(screenLongSide: max(bounds.width, bounds.height), scale: displayScale)
    }

    /// The screen in pixels with 2x zoom room, capped. On a Mac a 5K screen asks for about 12000 px,
    /// a full resolution decode of almost any photo; the cap keeps one page's bitmap near 250 MB at
    /// most. On a phone or tablet the gallery keeps several pages decoded at once, so the cap is
    /// lower there to stay well clear of the memory limit.
    static func decodeTarget(screenLongSide: CGFloat, scale: CGFloat) -> CGFloat {
        min(screenLongSide * scale * zoomHeadroom, maxDecodePixelDimension)
    }

    /// Decoded past the screen so a zoomed in image stays sharp.
    static let zoomHeadroom: CGFloat = 2

    #if os(macOS)
        static let maxDecodePixelDimension: CGFloat = 8192
    #elseif os(iOS)
        static let maxDecodePixelDimension: CGFloat = 4096
    #endif

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
                    serverURL: serverURL,
                    path: item.id,
                    signature: item.cacheSignature,
                    fallbackIcon: IconKit.document,
                    iconTint: Color.secondaryDS,
                    fileSize: item.size,
                    modified: item.dateModified
                )
                .blur(radius: Constants.placeholderBlur)
                .clipped()
                .allowsHitTesting(false)
            }

            switch phase {
            case let .gif(url):
                // GIFs play their real animation via `AnimatedImageView`: a decoded still would
                // only ever show the first frame.
                ZoomableScrollView(onZoomChange: onZoomChange) {
                    AnimatedImageView(fileURL: url)
                        .accessibilityElement()
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(.isImage)
                }
            case let .streaming(uiImage), let .loaded(uiImage):
                ZoomableScrollView(onZoomChange: onZoomChange) {
                    // An icon sized picture shows one point per pixel, as Quick Look does,
                    // instead of blown up to the screen; pinch still zooms it.
                    let iconSide = ThumbnailImage.isIconSized(uiImage) ? uiImage.cgImage : nil
                    Image(platformImage: uiImage).resizable().scaledToFit()
                        .frame(
                            maxWidth: iconSide.map { CGFloat($0.width) },
                            maxHeight: iconSide.map { CGFloat($0.height) }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(item.name)
                }
                .transition(.opacity)
                // Settle from a slight scale to 1 the moment the final image lands.
                .scaleEffect(phase.isFinal ? 1 : Constants.settleFromScale)
                .animation(DSMotion.galleryFade, value: phase.isFinal)
            case let .failed(message):
                PreviewErrorView(message: message)
            case .loading:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DSMotion.galleryFade, value: phase.hasImage)
        .task(id: "\(item.id)\u{0}\(item.cacheSignature)\u{0}\(isNear)") { await load() }
        #if os(macOS)
            .modifier(MacPreviewZoom())
        #endif
    }

    @MainActor
    private func load() async {
        guard isNear else {
            // Outside the retain window: release the decoded bitmap (and any GIF handle) so it
            // stops counting against resident memory.
            phase = .loading
            return
        }
        if loadedSignature != item.cacheSignature {
            loadedSignature = item.cacheSignature
            phase = .loading
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

        // The offline store is read off the main thread: each lookup stats files on disk, and a fast
        // swipe loads many pages.
        let item = item
        let serverURL = serverURL
        let store = offlineFileStore
        let isOnline = connectivity.isOnline()
        let source = await Task.detached(priority: .userInitiated) {
            GalleryImageSource.resolve(
                item: item,
                serverURL: serverURL,
                verifiedCopy: store.localURL(item),
                anyPinnedCopy: store.localURLIgnoringStaleness(item),
                isOnline: isOnline
            )
        }.value
        if Task.isCancelled {
            return
        }
        let url: URL
        switch source {
        case let .local(localURL):
            // A copy kept on the device decodes locally at final quality with no network.
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDownsampling.image(from: localURL, maxPixelDimension: target)
            }.value
            if Task.isCancelled {
                return
            }
            phase = decoded.map(GalleryImagePhase.loaded) ?? .failed(L10n.Gallery.loadFailed)
            return
        case .download:
            await decodeViaPreviewFile(target: target)
            return
        case let .stream(streamURL):
            // Online: stream progressively so the image ramps from rough to sharp with no spinner.
            url = streamURL
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
}

#Preview("Photo") {
    ImageGalleryPage(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: .distantPast, size: 2_400_000, kind: "jpg"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    )
}

#Preview("Animated") {
    ImageGalleryPage(
        item: FileItem(name: "loop.gif", path: "", dateModified: .distantPast, size: 512_000, kind: "gif"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    )
}

#Preview("Outside the window") {
    ImageGalleryPage(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: .distantPast, size: 2_400_000, kind: "jpg"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        isNear: false
    )
}
