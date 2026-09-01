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
        // `TextViewState` does the initial tree-sitter parse of the whole document; building it
        // on the main thread freezes the UI when a large source file opens. Build it off main,
        // then apply on the main actor. `StateBox` carries the non Sendable state across.
        let text = self.text
        let kind = self.kind
        Task {
            let box = await Task.detached(priority: .userInitiated) {
                let language = CodeEditorLanguage.language(forKind: kind)
                return StateBox(state: language.map { TextViewState(text: text, language: $0) } ?? TextViewState(text: text))
            }.value
            view.setState(box.state)
        }
        return view
    }

    private struct StateBox: @unchecked Sendable {
        let state: TextViewState
    }

    func updateUIView(_ uiView: TextView, context: Context) {
        uiView.isEditable = isEditable
        guard uiView.text != text else { return }
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, TextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        // `textViewDidChange` is a `nonisolated` protocol requirement (Runestone doesn't
        // annotate it `@MainActor`), so a `@MainActor` method can't satisfy it directly —
        // but UIKit only ever calls delegate methods on the main thread, so hopping in with
        // `assumeIsolated` is safe and lets us still touch the main-actor-isolated `text`.
        nonisolated func textViewDidChange(_ textView: TextView) {
            MainActor.assumeIsolated {
                text.wrappedValue = textView.text
            }
        }
    }
}
