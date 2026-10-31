#if os(macOS)
    import AppKit
    import CoreModels
    import Localization
    import Quartz

    /// When Space shows a toast instead of Quick Look: archives and known binaries have nothing
    /// to show, and a large file would have to come down whole before anything appears, so it
    /// is left to the preview, which streams video and audio. A copy saved offline is already on
    /// disk, so its size never matters.
    enum MacQuickLookPolicy {
        static let byteLimit: Int64 = 100 * 1024 * 1024

        static func refusal(for item: FileItem, isSavedOffline: Bool) -> String? {
            if item.isUnsupportedForPreview {
                return L10n.Browse.quickLookUnavailable
            }
            if !isSavedOffline, item.size > byteLimit {
                return L10n.Browse.quickLookTooLarge
            }
            return nil
        }
    }

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

        /// Closes the panel only while this table drives it: another window's table may own the
        /// shared panel by now.
        func close() {
            guard isVisible, let panel = QLPreviewPanel.shared(), panel.dataSource as AnyObject? === self else { return }
            panel.orderOut(nil)
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
