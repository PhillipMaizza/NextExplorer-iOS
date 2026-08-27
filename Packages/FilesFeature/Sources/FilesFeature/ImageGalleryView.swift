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

    @State private var selection: String

    init(items: [FileItem], initialItem: FileItem, serverURL: URL, onDismiss: @escaping () -> Void) {
        self.items = items
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        self._selection = State(initialValue: initialItem.id)
    }

    private var currentName: String {
        items.first { $0.id == selection }?.name ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryToolbar
            TabView(selection: $selection) {
                ForEach(items) { item in
                    ImageGalleryPage(item: item, serverURL: serverURL)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
        }
        .background(Color.black)
        .onAppear { OrientationLock.shared.unlock() }
        .onDisappear { OrientationLock.shared.lock() }
    }

    private var galleryToolbar: some View {
        HStack(spacing: Constants.toolbarSpacing) {
            DSCloseButton(action: onDismiss)

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
        }
        .padding(.horizontal, Constants.toolbarHorizontalPadding)
        .padding(.vertical, Constants.toolbarVerticalPadding)
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
