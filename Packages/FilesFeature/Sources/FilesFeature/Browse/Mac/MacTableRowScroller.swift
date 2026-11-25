#if os(macOS)
    import AppKit
    import SwiftUI

    private enum Metrics {
        static let layoutAttempts = 10
        static let retryDelay: TimeInterval = 0.05
    }

    /// Scrolls the Mac file table to a row, which a SwiftUI `Table` cannot do itself: it finds the
    /// `NSTableView` behind it. Placed in the table's background, it scrolls once per target.
    struct MacTableRowScroller: NSViewRepresentable {
        let row: Int?
        let target: String?
        var onScrolled: () -> Void = {}

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context: Context) {
            guard let row, let target else {
                context.coordinator.lastTarget = nil
                return
            }
            guard context.coordinator.lastTarget != target else { return }
            context.coordinator.lastTarget = target
            // After this pass: the table is laid out by then, and a row index before that is stale.
            Self.scroll(to: row, near: view, attemptsLeft: Metrics.layoutAttempts, onScrolled: onScrolled)
        }

        private static func scroll(
            to row: Int,
            near view: NSView,
            attemptsLeft: Int,
            onScrolled: @escaping () -> Void
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.retryDelay) {
                if let table = table(near: view), row < table.numberOfRows {
                    table.scrollRowToVisible(row)
                    if let window = table.window, window.firstResponder == nil || window.firstResponder === window {
                        window.makeFirstResponder(table)
                    }
                    onScrolled()
                } else if attemptsLeft > 0 {
                    scroll(to: row, near: view, attemptsLeft: attemptsLeft - 1, onScrolled: onScrolled)
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class Coordinator {
            var lastTarget: String?
        }

        /// The table whose enclosing view also holds this probe.
        private static func table(near view: NSView) -> NSTableView? {
            let probe = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            var ancestor = view.superview
            while let current = ancestor {
                if let table = tables(in: current).first(where: { covers(probe, $0) }) {
                    return table
                }
                ancestor = current.superview
            }
            return nil
        }

        private static func covers(_ point: NSPoint, _ table: NSTableView) -> Bool {
            guard !table.isHiddenOrHasHiddenAncestor, let scrollView = table.enclosingScrollView else { return false }
            return scrollView.convert(scrollView.bounds, to: nil).contains(point)
        }

        private static func tables(in view: NSView) -> [NSTableView] {
            if let table = view as? NSTableView {
                return [table]
            }
            return view.subviews.flatMap(tables(in:))
        }
    }

    private struct PreviewRow: Identifiable {
        let id: Int
    }

    #Preview("Scrolled to the last row") {
        Table((0 ..< 60).map(PreviewRow.init)) {
            TableColumn(Text(verbatim: "Row")) { row in Text(verbatim: "Row \(row.id)") }
        }
        .background { MacTableRowScroller(row: 59, target: "59") }
        .frame(width: 300, height: 240)
    }
#endif
