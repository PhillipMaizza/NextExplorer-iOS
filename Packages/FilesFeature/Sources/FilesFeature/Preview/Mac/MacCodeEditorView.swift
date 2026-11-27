#if os(macOS)
    import AppKit
    import DesignSystem
    import SwiftUI

    private enum Constants {
        /// Pause after the last keystroke before rehighlighting, so typing never waits on a parse.
        static let rehighlightDelay: Duration = .milliseconds(300)
        static let lineHeightMultiple: CGFloat = 1.8
        static let textInset = NSSize(width: .space12, height: .space24)
    }

    /// macOS counterpart of the Runestone backed editor: Runestone is UIKit only, so the Mac uses a
    /// monospaced `NSTextView` with the same inputs, colored by `MacSyntaxHighlighter` running the
    /// same tree sitter grammars off the main actor.
    struct CodeEditorView: NSViewRepresentable {
        let kind: String
        @Binding var text: String
        let isEditable: Bool
        /// Esc in the text: the text view would otherwise take it for word completion, so the
        /// preview's Close (and its save prompt) never heard it.
        var onEscape: (() -> Void)?

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            let textView = EditorTextView(usingTextLayoutManager: false)
            textView.isFocusedWhenShown = isEditable
            textView.autoresizingMask = .width
            textView.isVerticallyResizable = true
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            scrollView.documentView = textView
            textView.delegate = context.coordinator
            textView.drawsBackground = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textColor = .labelColor
            textView.textContainerInset = Constants.textInset
            textView.defaultParagraphStyle = Self.paragraphStyle
            textView.typingAttributes[.paragraphStyle] = Self.paragraphStyle
            textView.insertionPointColor = NSColor(Color.accent)
            textView.isRichText = false
            textView.allowsUndo = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isEditable = isEditable
            textView.string = text
            Self.applyBaseAttributes(to: textView)
            let ruler = MacLineNumberRuler(textView: textView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            context.coordinator.lastReportedText = text
            context.coordinator.onEscape = onEscape
            context.coordinator.attach(textView, kind: kind, ruler: ruler)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            let becameEditable = isEditable && !textView.isEditable
            textView.isEditable = isEditable
            if becameEditable, let textView = textView as? EditorTextView {
                textView.focusSoon()
            }
            context.coordinator.onEscape = onEscape
            guard context.coordinator.lastReportedText != text else { return }
            context.coordinator.lastReportedText = text
            textView.string = text
            Self.applyBaseAttributes(to: textView)
            context.coordinator.ruler?.reloadLines()
            context.coordinator.highlight(after: nil)
        }

        private static let paragraphStyle: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = Constants.lineHeightMultiple
            return style
        }()

        private static func applyBaseAttributes(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            var attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor,
            ]
            attributes[.font] = textView.font
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        /// A closed editor stops any pending rehighlight rather than parsing text nobody sees.
        static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
            coordinator.cancelHighlighting()
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            private let text: Binding<String>
            var lastReportedText: String
            var onEscape: (() -> Void)?
            private weak var textView: NSTextView?
            private(set) weak var ruler: MacLineNumberRuler?
            private var language: MacSyntaxLanguage?
            private var highlightTask: Task<Void, Never>?
            /// Bumped per request so a slower parse of older text can't paint over newer text.
            private var generation = 0

            init(text: Binding<String>) {
                self.text = text
                lastReportedText = text.wrappedValue
            }

            func attach(_ textView: NSTextView, kind: String, ruler: MacLineNumberRuler) {
                self.textView = textView
                self.ruler = ruler
                language = MacSyntaxLanguage.forKind(kind)
                highlight(after: nil)
            }

            func textView(_: NSTextView, doCommandBy selector: Selector) -> Bool {
                guard selector == #selector(NSResponder.cancelOperation(_:)), let onEscape else { return false }
                onEscape()
                return true
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                lastReportedText = textView.string
                text.wrappedValue = textView.string
                ruler?.reloadLines()
                highlight(after: Constants.rehighlightDelay)
            }

            func highlight(after delay: Duration?) {
                guard let language, let textView else { return }
                highlightTask?.cancel()
                generation += 1
                let requested = generation
                let snapshot = textView.string
                highlightTask = Task { [weak self] in
                    if let delay {
                        try? await Task.sleep(for: delay)
                    }
                    guard !Task.isCancelled else { return }
                    let spans = await Task.detached(priority: .userInitiated) {
                        MacSyntaxHighlighter.spans(for: snapshot, language: language)
                    }.value
                    guard !Task.isCancelled, let self, requested == generation else { return }
                    apply(spans, expectedText: snapshot)
                }
            }

            func cancelHighlighting() {
                highlightTask?.cancel()
                highlightTask = nil
            }

            /// Colors only: text, selection and undo history are left alone.
            private func apply(_ spans: [MacSyntaxSpan], expectedText: String) {
                guard let textView, let storage = textView.textStorage, textView.string == expectedText else { return }
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
                for span in spans {
                    guard NSMaxRange(span.range) <= storage.length,
                          let color = MacSyntaxHighlighter.color(forCapture: span.capture)
                    else { continue }
                    storage.addAttribute(.foregroundColor, value: color, range: span.range)
                }
                storage.endEditing()
            }
        }
    }

    private final class EditorTextView: NSTextView {
        var isFocusedWhenShown = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard isFocusedWhenShown, window != nil else { return }
            isFocusedWhenShown = false
            focusSoon()
        }

        func focusSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                window?.makeFirstResponder(self)
            }
        }
    }
#endif
