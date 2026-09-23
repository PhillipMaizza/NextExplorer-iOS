#if os(iOS)
    import Runestone
    import SwiftUI
    import TreeSitterBashRunestone
    import TreeSitterCPPRunestone
    import TreeSitterCRunestone
    import TreeSitterCSharpRunestone
    import TreeSitterCSSRunestone
    import TreeSitterGoRunestone
    import TreeSitterHTMLRunestone
    import TreeSitterJavaRunestone
    import TreeSitterJavaScriptRunestone
    import TreeSitterJSONRunestone
    import TreeSitterMarkdownRunestone
    import TreeSitterPHPRunestone
    import TreeSitterPythonRunestone
    import TreeSitterRubyRunestone
    import TreeSitterRustRunestone
    import TreeSitterSCSSRunestone
    import TreeSitterSQLRunestone
    import TreeSitterSwiftRunestone
    import TreeSitterTOMLRunestone
    import TreeSitterTSXRunestone
    import TreeSitterTypeScriptRunestone
    import TreeSitterYAMLRunestone

    /// Maps a `FileItem.kind` extension to the `TreeSitterLanguage` that renders it correctly —
    /// the same curated set of code kinds `FileTypeIcon`'s badge table dedicates a color to.
    /// `nil` falls back to plain, unhighlighted text (still fully editable).
    enum CodeEditorLanguage {
        static func language(forKind kind: String) -> TreeSitterLanguage? {
            switch kind.lowercased() {
            case "json": .json
            case "js", "jsx": .javaScript
            case "ts": .typeScript
            case "tsx": .tsx
            case "html", "htm": .html
            case "css": .css
            case "scss": .scss
            case "py": .python
            case "rb": .ruby
            case "php": .php
            case "go": .go
            case "rs": .rust
            case "java": .java
            case "c": .c
            case "cpp", "cc", "cxx": .cpp
            case "cs": .cSharp
            case "sql": .sql
            case "yml", "yaml": .yaml
            case "toml": .toml
            case "md", "markdown": .markdown
            case "sh", "bash", "zsh": .bash
            case "swift": .swift
            default: nil
            }
        }
    }

    /// Wraps Runestone's `TextView` (a `UIScrollView` subclass, not a `UITextView`) to get real
    /// tree-sitter syntax highlighting for code/text kinds — plain SwiftUI `TextEditor` has no
    /// concept of syntax highlighting at all.
    struct CodeEditorView: UIViewRepresentable {
        let kind: String
        @Binding var text: String
        let isEditable: Bool

        func makeUIView(context: Context) -> TextView {
            let view = TextView()
            view.editorDelegate = context.coordinator
            view.backgroundColor = .clear
            view.showLineNumbers = true
            view.isEditable = isEditable
            context.coordinator.applyDocument(text: text, kind: kind, to: view)
            return view
        }

        func updateUIView(_ uiView: TextView, context: Context) {
            uiView.isEditable = isEditable
            // Reapply the document only when the bound text diverges from what the editor itself
            // last reported, i.e. a genuine external change (first load, a reload, a save-driven
            // content swap) — never our own echoed keystrokes, and never mid-scroll. Applying it
            // through `setState` (below) rather than the raw `text` setter is what keeps Runestone's
            // line manager consistent; a bare `uiView.text = text` here would leave it half-built and
            // blank the document on the next lazy relayout a scroll triggers.
            guard context.coordinator.lastReportedText != text else { return }
            context.coordinator.applyDocument(text: text, kind: kind, to: uiView)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        private struct StateBox: @unchecked Sendable {
            let state: TextViewState
        }

        @MainActor
        final class Coordinator: NSObject, TextViewDelegate {
            private let text: Binding<String>
            /// The text the editor last held after an apply or a user edit. `updateUIView` compares
            /// against this to tell an external content change (reapply) from its own echoed edit
            /// (ignore), and `textViewDidChange` refuses to write anything back while we're the ones
            /// mutating the document.
            private(set) var lastReportedText: String
            private var isApplyingDocument = false
            /// Bumped on every apply so a slower off-main parse from a superseded apply can't land its
            /// `setState` after a newer one and overwrite the current document.
            private var applyGeneration = 0

            init(text: Binding<String>) {
                self.text = text
                lastReportedText = text.wrappedValue
            }

            /// Sets the whole document via `setState` — the only Runestone-sanctioned way to load
            /// content and the tree-sitter parse together. `TextViewState`'s parse runs off the main
            /// thread so a large file doesn't freeze the UI on open; `StateBox` carries the non
            /// Sendable state back across.
            func applyDocument(text newText: String, kind: String, to view: TextView) {
                lastReportedText = newText
                isApplyingDocument = true
                applyGeneration += 1
                let generation = applyGeneration
                Task {
                    let box = await Task.detached(priority: .userInitiated) {
                        let language = CodeEditorLanguage.language(forKind: kind)
                        return StateBox(state: language.map { TextViewState(text: newText, language: $0) } ?? TextViewState(text: newText))
                    }.value
                    // A newer apply superseded this one while it parsed — drop its stale result and
                    // leave `isApplyingDocument` for the newer apply to clear.
                    guard generation == applyGeneration else { return }
                    view.setState(box.state)
                    isApplyingDocument = false
                }
            }

            /// `textViewDidChange` is a `nonisolated` protocol requirement (Runestone doesn't
            /// annotate it `@MainActor`), so a `@MainActor` method can't satisfy it directly —
            /// but UIKit only ever calls delegate methods on the main thread, so hopping in with
            /// `assumeIsolated` is safe and lets us still touch the main-actor-isolated `text`.
            nonisolated func textViewDidChange(_ textView: TextView) {
                MainActor.assumeIsolated {
                    // Ignore the change callbacks Runestone fires while we apply a document (and any
                    // it emits during a scroll relayout): only a real user edit should flow back into
                    // the binding, otherwise a transient value can overwrite the file with empty text.
                    guard !isApplyingDocument else { return }
                    lastReportedText = textView.text
                    text.wrappedValue = textView.text
                }
            }
        }
    }
#endif
