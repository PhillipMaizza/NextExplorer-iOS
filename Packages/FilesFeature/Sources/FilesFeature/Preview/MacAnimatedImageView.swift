#if os(macOS)
    import SwiftUI

    /// macOS GIF player: decodes the capped frame set off the main actor, then steps through it on
    /// the display timeline at the loop's uniform frame rate.
    struct AnimatedImageView: View {
        let fileURL: URL

        @State private var frames: AnimatedImageDecoder.Frames?

        var body: some View {
            Group {
                if let frames, frames.images.count > 1 {
                    TimelineView(.animation) { timeline in
                        frameImage(frames.images[frameIndex(at: timeline.date, in: frames)])
                    }
                } else if let frame = frames?.images.first {
                    frameImage(frame)
                } else {
                    Color.clear
                }
            }
            .task(id: fileURL) {
                let url = fileURL
                let decoded = await Task.detached(priority: .userInitiated) {
                    AnimatedImageDecoder.decode(at: url)
                }.value
                guard !Task.isCancelled else { return }
                frames = decoded
            }
        }

        private func frameImage(_ image: CGImage) -> some View {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        }

        private func frameIndex(at date: Date, in frames: AnimatedImageDecoder.Frames) -> Int {
            guard frames.duration > 0 else { return 0 }
            let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: frames.duration) / frames.duration
            return min(frames.images.count - 1, Int(progress * Double(frames.images.count)))
        }
    }
#endif
