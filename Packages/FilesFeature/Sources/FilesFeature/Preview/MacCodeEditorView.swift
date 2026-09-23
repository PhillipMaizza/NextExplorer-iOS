#if os(macOS)
    import AppKit
    import SwiftUI

    private enum Constants {
        /// Pause after the last keystroke before re-highlighting, so typing never waits on a parse.
        static let rehighlightDelay: Duration = .milliseconds(300)
    }

    /// macOS counterpart of the Runestone backed editor: Runestone is UIKit only, so the Mac uses a
    /// monospaced `NSTextView` with the same inputs, colored by `MacSyntaxHighlighter` running the
    /// same tree-sitter grammars off the main actor.
    struct CodeEditorView: NSViewRepresentable {
        let kind: String
        @Binding var text: String
        let isEditable: Bool

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSTextView.scrollableTextView()
            scrollView.drawsBackground = false
            guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
            textView.delegate = context.coordinator
            textView.drawsBackground = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textColor = .labelColor
            textView.isRichText = false
            textView.allowsUndo = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isEditable = isEditable
            textView.string = text
            context.coordinator.lastReportedText = text
            context.coordinator.attach(textView, kind: kind)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            textView.isEditable = isEditable
            guard context.coordinator.lastReportedText != text else { return }
            context.coordinator.lastReportedText = text
            textView.string = text
            context.coordinator.highlight(after: nil)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            private let text: Binding<String>
            var lastReportedText: String
            private weak var textView: NSTextView?
            private var language: MacSyntaxLanguage?
            private var highlightTask: Task<Void, Never>?
            /// Bumped per request so a slower parse of older text can't paint over newer text.
            private var generation = 0

            init(text: Binding<String>) {
                self.text = text
                lastReportedText = text.wrappedValue
            }

            func attach(_ textView: NSTextView, kind: String) {
                self.textView = textView
                language = MacSyntaxLanguage.forKind(kind)
                highlight(after: nil)
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                lastReportedText = textView.string
                text.wrappedValue = textView.string
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
#endif
