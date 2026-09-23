#if os(macOS)
    import AppKit
    import SwiftUI

    /// macOS counterpart of the Runestone backed editor: Runestone is UIKit only, so the Mac uses a
    /// plain monospaced `NSTextView` with the same inputs. Syntax highlighting is not wired yet.
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
            textView.isRichText = false
            textView.allowsUndo = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isEditable = isEditable
            textView.string = text
            context.coordinator.lastReportedText = text
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            textView.isEditable = isEditable
            guard context.coordinator.lastReportedText != text else { return }
            context.coordinator.lastReportedText = text
            textView.string = text
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            private let text: Binding<String>
            var lastReportedText: String

            init(text: Binding<String>) {
                self.text = text
                lastReportedText = text.wrappedValue
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                lastReportedText = textView.string
                text.wrappedValue = textView.string
            }
        }
    }
#endif
