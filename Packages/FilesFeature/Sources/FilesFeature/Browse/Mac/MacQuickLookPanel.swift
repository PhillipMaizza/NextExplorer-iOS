#if os(macOS)
    import AppKit
    import CoreModels
    import Localization
    import Quartz
    import SwiftUI

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

        /// Sits in the table window's responder chain, where the panel looks for whoever
        /// controls it, the way AppKit asks to be driven.
        let responder = MacQuickLookResponder()

        override init() {
            super.init()
            responder.owner = self
        }

        /// Something is to be shown, so this table asks for the panel.
        var hasFileToShow: Bool {
            url != nil
        }

        func show(_ url: URL, onMove: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
            self.url = url
            self.onMove = onMove
            self.onClose = onClose
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.updateController()
            // Outside a chain the panel can find (no window yet), drive it directly as before.
            if panel.currentController as AnyObject? !== responder {
                attach(to: panel)
            }
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }

        func attach(to panel: QLPreviewPanel) {
            panel.dataSource = self
            panel.delegate = self
        }

        func detach(from panel: QLPreviewPanel) {
            guard panel.dataSource as AnyObject? === self else { return }
            panel.dataSource = nil
            panel.delegate = nil
        }

        /// Closes the panel only while this table drives it: another window's table may own the
        /// shared panel by now. The panel holds its data source and delegate unretained, so they
        /// are cleared here too: a table that goes away must never leave the panel pointing at it.
        func close() {
            guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
                  panel.dataSource as AnyObject? === self else { return }
            if panel.isVisible {
                panel.orderOut(nil)
            }
            url = nil
            detach(from: panel)
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

    /// The panel's controller in the responder chain: accepts it while its table has a file to
    /// show, and hands it the data source and delegate.
    @MainActor
    final class MacQuickLookResponder: NSResponder {
        weak var owner: MacQuickLookPanel?

        override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
            MainActor.assumeIsolated { owner?.hasFileToShow ?? false }
        }

        override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                if let panel {
                    owner?.attach(to: panel)
                }
            }
        }

        override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                if let panel {
                    owner?.detach(from: panel)
                }
            }
        }

        /// Joins `window`'s responder chain just after the window itself.
        func insert(into window: NSWindow) {
            guard nextResponder == nil, window.nextResponder !== self else { return }
            nextResponder = window.nextResponder
            window.nextResponder = self
        }

        /// Leaves the chain wherever it sits, so other tables' responders stay linked.
        func remove(from window: NSWindow) {
            var link: NSResponder = window
            while let next = link.nextResponder {
                if next === self {
                    link.nextResponder = nextResponder
                    nextResponder = nil
                    return
                }
                link = next
            }
        }
    }

    /// Puts the table's Quick Look responder into the chain of whichever window shows it.
    struct MacQuickLookResponderAnchor: NSViewRepresentable {
        let responder: MacQuickLookResponder

        func makeNSView(context _: Context) -> AnchorView {
            AnchorView(responder: responder)
        }

        func updateNSView(_: AnchorView, context _: Context) {}

        static func dismantleNSView(_ view: AnchorView, coordinator _: ()) {
            view.leaveWindow()
        }

        final class AnchorView: NSView {
            private let responder: MacQuickLookResponder
            private weak var joinedWindow: NSWindow?

            init(responder: MacQuickLookResponder) {
                self.responder = responder
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window !== joinedWindow else { return }
                leaveWindow()
                if let window {
                    responder.insert(into: window)
                    joinedWindow = window
                }
            }

            func leaveWindow() {
                if let joinedWindow {
                    responder.remove(from: joinedWindow)
                }
                joinedWindow = nil
            }
        }
    }

    #Preview("Quick Look anchor") {
        Text(verbatim: "notes.txt")
            .padding(.space16)
            .background(MacQuickLookResponderAnchor(responder: MacQuickLookResponder()))
    }
#endif
