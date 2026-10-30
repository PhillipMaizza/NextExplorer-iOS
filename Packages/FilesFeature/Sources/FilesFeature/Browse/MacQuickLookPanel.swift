#if os(macOS)
    import AppKit
    import Quartz

    /// Drives the system Quick Look panel for the file table, the way Finder does: the panel
    /// shows the selected file, and Up and Down in the panel move the table's selection, which
    /// the table answers by showing the next file.
    @MainActor
    final class MacQuickLookPanel: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var url: URL?
        private var onMove: (Int) -> Void = { _ in }
        private var onClose: () -> Void = {}

        private static let upArrowKeyCode: UInt16 = 126
        private static let downArrowKeyCode: UInt16 = 125

        var isVisible: Bool {
            QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
        }

        func show(_ url: URL, onMove: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
            self.url = url
            self.onMove = onMove
            self.onClose = onClose
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = self
            panel.delegate = self
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }

        func close() {
            guard isVisible else { return }
            QLPreviewPanel.shared().orderOut(nil)
        }

        nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
            MainActor.assumeIsolated { url == nil ? 0 : 1 }
        }

        nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> (any QLPreviewItem)! {
            MainActor.assumeIsolated { url as NSURL? }
        }

        nonisolated func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard let event, event.type == .keyDown else { return false }
            let keyCode = event.keyCode
            return MainActor.assumeIsolated {
                switch keyCode {
                case Self.upArrowKeyCode:
                    onMove(-1)
                    return true
                case Self.downArrowKeyCode:
                    onMove(1)
                    return true
                default:
                    return false
                }
            }
        }

        nonisolated func windowWillClose(_: Notification) {
            MainActor.assumeIsolated { onClose() }
        }
    }
#endif
