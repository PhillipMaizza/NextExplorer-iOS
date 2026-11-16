#if os(macOS)
    import AppKit
    import SwiftUI

    /// Scrolls the Mac file table to a row, which a SwiftUI `Table` cannot do itself: it finds the
    /// `NSTableView` behind it. Placed in the table's background, it scrolls once per target.
    struct MacTableRowScroller: NSViewRepresentable {
        let row: Int?
        let target: String?

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context: Context) {
            guard let row, let target, context.coordinator.lastTarget != target else { return }
            context.coordinator.lastTarget = target
            // After this pass: the table is laid out by then, and a row index before that is stale.
            DispatchQueue.main.async {
                guard let table = Self.table(near: view), row < table.numberOfRows else { return }
                table.scrollRowToVisible(row)
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
            var ancestor = view.superview
            while let current = ancestor {
                if let table = firstTable(in: current) {
                    return table
                }
                ancestor = current.superview
            }
            return nil
        }

        private static func firstTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView {
                return table
            }
            for child in view.subviews {
                if let table = firstTable(in: child) {
                    return table
                }
            }
            return nil
        }
    }
#endif
