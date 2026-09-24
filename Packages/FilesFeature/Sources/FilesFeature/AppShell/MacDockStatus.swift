#if os(macOS)
    import AppKit
    import SwiftUI

    private enum Metrics {
        static let barHeight: CGFloat = 10
        static let barInset: CGFloat = 12
        static let barBottom: CGFloat = 8
    }

    /// Upload progress on the Dock icon: a badge with the files still to go and a bar under the
    /// icon, both cleared once the queue drains. The Dock keeps showing it while the app is in
    /// the background, which is exactly when a long upload needs watching.
    struct MacDockUploadStatus: ViewModifier {
        let remaining: Int
        let progress: Double?

        func body(content: Content) -> some View {
            content
                .onChange(of: remaining, initial: true) { _, _ in update() }
                .onChange(of: progress) { _, _ in update() }
        }

        private func update() {
            let dockTile = NSApp.dockTile
            dockTile.badgeLabel = remaining > 0 ? "\(remaining)" : nil
            if let progress, remaining > 0 {
                let view = dockTile.contentView as? DockProgressView ?? DockProgressView()
                view.progress = progress
                dockTile.contentView = view
            } else {
                dockTile.contentView = nil
            }
            dockTile.display()
        }
    }

    /// The app icon with a thin progress bar along its bottom edge.
    private final class DockProgressView: NSView {
        var progress: Double = 0 {
            didSet { needsDisplay = true }
        }

        override func draw(_: NSRect) {
            NSApp.applicationIconImage?.draw(in: bounds)
            let track = NSRect(
                x: Metrics.barInset,
                y: Metrics.barBottom,
                width: bounds.width - Metrics.barInset * 2,
                height: Metrics.barHeight
            )
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()
            var fill = track
            fill.size.width = track.width * min(max(progress, 0), 1)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
        }
    }
#endif
