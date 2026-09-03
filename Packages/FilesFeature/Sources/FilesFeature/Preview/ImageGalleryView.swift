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
    /// How many pages either side of the current one keep a decoded bitmap resident. A page
    /// style `TabView` materializes every child, so without this a folder of hundreds of photos
    /// would hold a decoded image per page and jetsam. Pages outside the window drop their
    /// bitmap and re decode when swiped back near.
    static let retainWindow = 2
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

    var body: some View {
        NavigationStack {
            // Full-bleed on every edge: the bars float over the image, so toggling them
            // never resizes or reflows the content — the image stays perfectly still
            // while the chrome fades, matching the Photos viewer.
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ImageGalleryPage(item: item, serverURL: serverURL, isNear: isNear(index))
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 && !areControlsHidden ? .always : .never))
            .ignoresSafeArea()
            // A rename changes the current image's id (it's path-derived); deleting one drops
            // it. Close if that emptied the gallery, otherwise hold the same slot so a dangling
            // `selection` lands on the neighbour.
            .onChange(of: items) { oldItems, newItems in
                if newItems.isEmpty { onDismiss(); return }
                guard !newItems.contains(where: { $0.id == selection }) else { return }
                let slot = oldItems.firstIndex { $0.id == selection } ?? 0
                selection = (newItems.indices.contains(slot) ? newItems[slot] : newItems[newItems.count - 1]).id
            }
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
            .toolbar(areControlsHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar(areControlsHidden ? .hidden : .visible, for: .bottomBar)
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

private struct ImageGalleryPage: View {
    let item: FileItem
    let serverURL: URL
    /// When false (page is outside the retain window) the decoded bitmap is dropped so a large
    /// folder can't hold an image per page. Flips back true when swiped near, triggering a
    /// re decode.
    var isNear: Bool = true
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
                DSSpinner()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(item.id)\u{0}\(isNear)") {
            guard isNear else {
                // Outside the retain window: release the decoded bitmap (and any GIF handle)
                // so it stops counting against resident memory.
                image = nil
                gifURL = nil
                errorMessage = nil
                return
            }
            guard image == nil, gifURL == nil else { return }
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
                // Swiping away mid load cancels this task; that is not a load failure, so leave
                // the spinner rather than flashing an error screen the user already left.
                if !Task.isCancelled {
                    errorMessage = (error as? FilesClientError)?.userMessage ?? L10n.Gallery.loadFailed
                }
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
