import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let playButtonSize: CGFloat = .size64
    static let playButtonShadowRadius: CGFloat = 8
    /// A video with no poster frame shows its file icon at this size behind the play button.
    static let posterFallbackSize: CGFloat = .size96
}

/// A video or audio file in the gallery. It plays in place once started (the file opened from the
/// list starts on its own) and stops when swiped away; until then a video shows its poster frame
/// and audio its file summary, each with a play button.
struct MediaGalleryPage: View {
    let item: FileItem
    let serverURL: URL
    let isPlaying: Bool
    /// The space the gallery's bars take: the player keeps its own controls clear of them, and
    /// fills the screen again once the bars hide.
    var contentInsets = EdgeInsets()
    let onPlay: () -> Void

    var body: some View {
        if isPlaying {
            MediaPreview(item: item, serverURL: serverURL, isEmbedded: true)
                .padding(contentInsets)
                .background(Color.black)
        } else if item.isVideo {
            poster
        } else {
            FileSummaryView(item: item, artworkServerURL: serverURL) {
                DSButton(L10n.Media.play, icon: IconKit.play, style: .primary, action: onPlay)
            }
        }
    }

    private var poster: some View {
        ZStack {
            Color.black
            if item.supportsThumbnail {
                ThumbnailImage(
                    serverURL: serverURL,
                    path: item.id,
                    signature: item.cacheSignature,
                    fallbackIcon: IconKit.document,
                    fallbackKind: item.kind,
                    iconTint: Color.secondaryDS,
                    fallbackSize: Constants.posterFallbackSize
                )
                .scaledToFit()
                .allowsHitTesting(false)
            }
            Button(action: onPlay) {
                IconKit.playCircle
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.playButtonSize, height: Constants.playButtonSize)
                    .foregroundStyle(.white)
                    .shadow(radius: Constants.playButtonShadowRadius)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Media.play)
        }
    }
}

#Preview("Video poster") {
    MediaGalleryPage(
        item: FileItem(name: "clip.mp4", path: "Videos", dateModified: .distantPast, size: 1_048_576, kind: "mp4"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        isPlaying: false,
        onPlay: {}
    )
}

#Preview("Audio") {
    MediaGalleryPage(
        item: FileItem(name: "song.mp3", path: "Music", dateModified: .distantPast, size: 4_194_304, kind: "mp3"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        isPlaying: false,
        onPlay: {}
    )
}

#Preview("Playing") {
    MediaGalleryPage(
        item: FileItem(name: "clip.mp4", path: "Videos", dateModified: .distantPast, size: 1_048_576, kind: "mp4"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        isPlaying: true,
        contentInsets: EdgeInsets(top: .size96, leading: 0, bottom: .size96, trailing: 0),
        onPlay: {}
    )
}
