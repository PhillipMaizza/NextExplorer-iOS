import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    /// Two toggles closer than this are the same tap heard twice.
    static let toggleDebounce: TimeInterval = 0.5
    /// How many pages either side of the current one keep their content (a decoded bitmap, a
    /// Quick Look document, a text view). A page style `TabView` materializes every child, so
    /// without this a folder of hundreds of files would hold one per page and jetsam. Pages
    /// outside the window let go and load again when swiped back near.
    static let retainWindow = 2
}

/// What the preview already fetched for the file it opened on, so that page shows it at once
/// instead of asking the server again.
struct GalleryPreload: Equatable {
    var itemID: String?
    var fileURL: URL?
    var text: String?

    func fileURL(for item: FileItem) -> URL? {
        item.id == itemID ? fileURL : nil
    }

    func text(for item: FileItem) -> String? {
        item.id == itemID ? text : nil
    }
}

/// The actions the gallery's bars offer on the file on screen, routed back to the caller. `nil`
/// hides a button (no permission, or no editor for the file).
struct FileGalleryActions {
    var onShare: ((FileItem) -> Void)?
    var onRename: ((FileItem) -> Void)?
    var onDownload: ((FileItem) -> Void)?
    var offline: ((FileItem) -> PreviewOfflineAction?)?
    var onDelete: ((FileItem) -> Void)?
    var onInfo: ((FileItem) -> Void)?
    /// Opens the folder picker; the file leaves the gallery once it has moved.
    var onMove: ((FileItem) -> Void)?
    /// Stages the file for pasting in another folder, as the list's Copy does.
    var onCopy: ((FileItem) -> Void)?
    /// Hands a text file to the editor.
    var onEdit: ((FileItem) -> Void)?
}

/// Swipeable full screen viewer for every file in the current folder, not just the one tapped:
/// images, videos, documents, text and the rest page side by side instead of
/// dismissing back to the list between each. Every fetch goes through `FilesClient`'s on disk
/// cache, so revisiting a page in the same session never asks the server again. On a Mac only
/// images page here, one at a time; the preview router's arrow keys step through the folder.
struct FileGalleryView: View {
    let items: [FileItem]
    let serverURL: URL
    let onDismiss: () -> Void
    private let actions: FileGalleryActions
    /// What the preview fetched for the file it opened on.
    private let preload: GalleryPreload
    /// Reports the page currently on screen as the user swipes, so the caller can keep the
    /// `.zoom` transition source (and the underlying list's scroll position) on the file the
    /// cover will actually dismiss back to, not the one first tapped.
    private let onCurrentItemChange: (FileItem) -> Void

    @State private var selection: String
    /// The pages on screen: `items`, taken over together with the selection in one update. A page
    /// `TabView` whose selected page vanishes jumps to its first page on its own, so a deleted or
    /// renamed file must never leave the selection pointing at a page that is gone.
    @State private var pages: [FileItem]
    /// Single tap toggles the nav bar + bottom action bar + system overlays, like the Photos
    /// app's full screen viewer.
    @State private var areControlsHidden = false
    /// The video or audio file playing in place. The file opened from the list starts on its own;
    /// one swiped to waits for its play button, and swiping away stops it.
    @State private var playingItemID: String?
    /// The zip, rar or office document whose Open button presented it on its own.
    @State private var openedItem: FileItem?
    /// The safe area's frame in the window: its distance from the window's edges is the bars' space.
    @State private var safeFrame = CGRect.zero
    /// When the bars last toggled: a page whose own view forwards its taps can be heard by the
    /// pager too, and one tap must toggle once.
    @State private var lastToggle = Date.distantPast

    init(
        items: [FileItem],
        initialItem: FileItem,
        serverURL: URL,
        preload: GalleryPreload = GalleryPreload(),
        actions: FileGalleryActions = FileGalleryActions(),
        onDismiss: @escaping () -> Void,
        onCurrentItemChange: @escaping (FileItem) -> Void = { _ in }
    ) {
        self.items = items
        self.serverURL = serverURL
        self.preload = preload
        self.actions = actions
        self.onDismiss = onDismiss
        self.onCurrentItemChange = onCurrentItemChange
        _selection = State(initialValue: initialItem.id)
        // A refresh or a search change between the tap and the gallery opening can drop the file it
        // opens on; it then opens alone rather than on a blank page.
        _pages = State(initialValue: items.contains { $0.id == initialItem.id } ? items : [initialItem])
        _playingItemID = State(initialValue: PreviewKind(initialItem) == .media ? initialItem.id : nil)
    }

    private var currentItem: FileItem? {
        pages.first { $0.id == selection }
    }

    private var currentName: String {
        currentItem?.name ?? ""
    }

    #if os(macOS)
        private var pager: some View {
            Group {
                if let index = pages.firstIndex(where: { $0.id == selection }) {
                    ImageGalleryPage(item: pages[index], serverURL: serverURL, isNear: true)
                        .id(pages[index].id)
                }
            }
        }
    #else
        /// SwiftUI's own paging rather than a page style `TabView`: that one is a collection view
        /// underneath which took the bars as content insets, sized its pages wrong and now and then
        /// snapped back to the first page. A lazy stack also builds only the pages near the screen.
        private func pager(barInsets: EdgeInsets) -> some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        FileGalleryPage(
                            item: item,
                            serverURL: serverURL,
                            isNear: isNear(index),
                            preload: preload,
                            isPlaying: playingItemID == item.id,
                            barInsets: barInsets,
                            onPlay: { playingItemID = item.id },
                            onOpen: { openedItem = item },
                            onToggleBars: toggleControls
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .clipped()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrolledID)
            .scrollIndicators(.hidden)
        }

        /// The page on screen as the scroll position wants it.
        private var scrolledID: Binding<String?> {
            Binding(get: { selection }, set: { id in
                if let id {
                    selection = id
                }
            })
        }

        private var pageIndex: Binding<Int> {
            Binding(
                get: { pages.firstIndex { $0.id == selection } ?? 0 },
                set: { index in
                    guard pages.indices.contains(index) else { return }
                    selection = pages[index].id
                }
            )
        }

        @ViewBuilder
        private var pageDots: some View {
            // Dots only for a run of photos; a folder of mixed files pages without them.
            if pages.count > 1, !areControlsHidden, pages.allSatisfy({ PreviewKind($0) == .image }) {
                GalleryPageControl(numberOfPages: pages.count, currentPage: pageIndex)
                    .padding(.bottom, .space8)
                    .transition(.opacity)
            }
        }
    #endif

    var body: some View {
        NavigationStack {
            // Full bleed on every edge: the bars float over the page, so toggling them never
            // resizes or reflows an image; it stays perfectly still while the chrome fades.
            fullBleedPager
            #if os(iOS)
                .overlay(alignment: .bottom) { pageDots }
                .fullScreenCover(item: $openedItem) { opened in
                    if PreviewKind(opened) == .archive {
                        ArchiveBrowserView(item: opened, serverURL: serverURL, onDismiss: { openedItem = nil })
                    } else {
                        QuickLookCover(item: opened, serverURL: serverURL, onDismiss: { openedItem = nil })
                    }
                }
            #endif
                // A rename changes the current file's id (it's path derived); deleting one drops
                // it. Close if that emptied the gallery, otherwise hold the same slot so a dangling
                // `selection` lands on the neighbour.
                .onChange(of: items) { _, newItems in
                    if newItems.isEmpty {
                        onDismiss(); return
                    }
                    var update = Transaction()
                    update.disablesAnimations = true
                    withTransaction(update) {
                        if !newItems.contains(where: { $0.id == selection }) {
                            let slot = pages.firstIndex { $0.id == selection } ?? 0
                            selection = newItems[min(slot, newItems.count - 1)].id
                        }
                        pages = newItems
                    }
                }
                // Keep the caller's zoom source and list scroll aligned with the page swiped to,
                // and stop whatever played on the page left behind.
                .onChange(of: selection) { _, _ in
                    playingItemID = nil
                    currentItem.map(onCurrentItemChange)
                }
                .contentShape(Rectangle())
                // A short fade, nothing more: the page is full bleed and never moves, so only the
                // chrome itself crossfades.
                .onTapGesture(perform: toggleControls)
                .previewChrome(
                    title: currentName,
                    systemShare: currentItem.map { .remote($0, serverURL: serverURL) } ?? .unavailable,
                    onShareLink: currentItemAction(actions.onShare),
                    onRename: currentItemAction(actions.onRename),
                    onDownload: currentItemAction(actions.onDownload),
                    onDelete: currentItemAction(actions.onDelete),
                    onInfo: currentItemAction(actions.onInfo),
                    onMove: currentItemAction(actions.onMove),
                    onCopy: currentItemAction(actions.onCopy),
                    offline: currentItem.flatMap { actions.offline?($0) },
                    onEdit: currentItem.map { PreviewKind($0) == .text } == true
                        ? currentItemAction(actions.onEdit)
                        : nil,
                    hasFrostedBars: true,
                    hasBottomBar: false,
                    file: currentItem,
                    onClose: onDismiss
                )
                .hidesNavigationBar(areControlsHidden)
                .hidesBottomBar(areControlsHidden)
                .statusBarHidden(areControlsHidden)
        }
        .onAppear { OrientationLock.shared.unlock() }
        .onDisappear { OrientationLock.shared.lock() }
    }

    /// The pager, full bleed on every edge. The page `TabView` itself stays inside the safe area and
    /// only its pages bleed out, so the bars' space is read from a clear view beside it: its distance
    /// from the window's top and bottom edges. A reader wrapping the pager instead handed the insets
    /// to the pager's scroll view, which then sized its pages wrong and dropped swipes.
    private var fullBleedPager: some View {
        #if os(iOS)
            ZStack {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { safeFrame = $0 }
                pager(barInsets: barInsets)
                    .ignoresSafeArea()
            }
        #else
            pager
                .ignoresSafeArea()
        #endif
    }

    /// The bars' space at the top and bottom of the window.
    private var barInsets: EdgeInsets {
        let window = PlatformScreen.bounds
        guard !safeFrame.isEmpty, !window.isEmpty else { return EdgeInsets() }
        return EdgeInsets(
            top: max(0, safeFrame.minY),
            leading: 0,
            bottom: max(0, window.height - safeFrame.maxY),
            trailing: 0
        )
    }

    private func toggleControls() {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > Constants.toggleDebounce else { return }
        lastToggle = now
        withAnimation(DSMotion.galleryFade) {
            areControlsHidden.toggle()
        }
    }

    /// Whether page `index` is close enough to the current selection to keep its content.
    private func isNear(_ index: Int) -> Bool {
        guard let selected = pages.firstIndex(where: { $0.id == selection }) else { return false }
        return abs(index - selected) <= Constants.retainWindow
    }

    /// Binds one of the caller's `(FileItem) -> Void` toolbar callbacks to whichever file is
    /// currently on screen, or `nil` when the caller didn't supply that action.
    private func currentItemAction(_ action: ((FileItem) -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        return { currentItem.map(action) }
    }
}

private enum PreviewSample {
    static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    static let photo = FileItem(name: "vacation.jpg", path: "", dateModified: .distantPast, size: 0, kind: "jpg")
    static let report = FileItem(name: "report.pdf", path: "", dateModified: .distantPast, size: 0, kind: "pdf")
    static let notes = FileItem(name: "notes.txt", path: "", dateModified: .distantPast, size: 0, kind: "txt")
}

#Preview("Single image") {
    FileGalleryView(
        items: [PreviewSample.photo],
        initialItem: PreviewSample.photo,
        serverURL: PreviewSample.serverURL,
        onDismiss: {}
    )
}

#Preview("Mixed folder") {
    FileGalleryView(
        items: [PreviewSample.photo, PreviewSample.report, PreviewSample.notes],
        initialItem: PreviewSample.report,
        serverURL: PreviewSample.serverURL,
        actions: FileGalleryActions(onShare: { _ in }, onDelete: { _ in }, onEdit: { _ in }),
        onDismiss: {}
    )
}
