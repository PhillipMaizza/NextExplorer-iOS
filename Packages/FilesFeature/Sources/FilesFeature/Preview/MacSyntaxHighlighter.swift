#if os(macOS)
    import AppKit
    import Foundation
    import TreeSitter
    import TreeSitterBash
    import TreeSitterBashQueries
    import TreeSitterC
    import TreeSitterCPP
    import TreeSitterCPPQueries
    import TreeSitterCQueries
    import TreeSitterCSharp
    import TreeSitterCSharpQueries
    import TreeSitterCSS
    import TreeSitterCSSQueries
    import TreeSitterGo
    import TreeSitterGoQueries
    import TreeSitterHTML
    import TreeSitterHTMLQueries
    import TreeSitterJava
    import TreeSitterJavaQueries
    import TreeSitterJavaScript
    import TreeSitterJavaScriptQueries
    import TreeSitterJSON
    import TreeSitterJSONQueries
    import TreeSitterMarkdown
    import TreeSitterMarkdownQueries
    import TreeSitterPHP
    import TreeSitterPHPQueries
    import TreeSitterPython
    import TreeSitterPythonQueries
    import TreeSitterRuby
    import TreeSitterRubyQueries
    import TreeSitterRust
    import TreeSitterRustQueries
    import TreeSitterSCSS
    import TreeSitterSCSSQueries
    import TreeSitterSQL
    import TreeSitterSQLQueries
    import TreeSitterSwift
    import TreeSitterSwiftQueries
    import TreeSitterTOML
    import TreeSitterTOMLQueries
    import TreeSitterTSX
    import TreeSitterTSXQueries
    import TreeSitterTypeScript
    import TreeSitterTypeScriptQueries
    import TreeSitterYAML
    import TreeSitterYAMLQueries

    /// A tree-sitter grammar plus its highlight queries. TypeScript, TSX, SCSS and C++ layer their
    /// queries over the language they extend, the same way Runestone composes them on iOS.
    struct MacSyntaxLanguage: @unchecked Sendable {
        let language: UnsafePointer<TSLanguage>?
        let queryURLs: [URL]

        /// Same curated kinds as the iOS editor's `CodeEditorLanguage`.
        static func forKind(_ kind: String) -> MacSyntaxLanguage? {
            switch kind.lowercased() {
            case "json": MacSyntaxLanguage(language: tree_sitter_json(), queryURLs: [TreeSitterJSONQueries.Query.highlightsFileURL])
            case "js", "jsx": MacSyntaxLanguage(language: tree_sitter_javascript(), queryURLs: [TreeSitterJavaScriptQueries.Query.highlightsFileURL])
            case "ts": MacSyntaxLanguage(language: tree_sitter_typescript(), queryURLs: [TreeSitterJavaScriptQueries.Query.highlightsFileURL, TreeSitterTypeScriptQueries.Query.highlightsFileURL])
            case "tsx": MacSyntaxLanguage(language: tree_sitter_tsx(), queryURLs: [TreeSitterJavaScriptQueries.Query.highlightsFileURL, TreeSitterTypeScriptQueries.Query.highlightsFileURL, TreeSitterTSXQueries.Query.highlightsFileURL])
            case "html", "htm": MacSyntaxLanguage(language: tree_sitter_html(), queryURLs: [TreeSitterHTMLQueries.Query.highlightsFileURL])
            case "css": MacSyntaxLanguage(language: tree_sitter_css(), queryURLs: [TreeSitterCSSQueries.Query.highlightsFileURL])
            case "scss": MacSyntaxLanguage(language: tree_sitter_scss(), queryURLs: [TreeSitterCSSQueries.Query.highlightsFileURL, TreeSitterSCSSQueries.Query.highlightsFileURL])
            case "py": MacSyntaxLanguage(language: tree_sitter_python(), queryURLs: [TreeSitterPythonQueries.Query.highlightsFileURL])
            case "rb": MacSyntaxLanguage(language: tree_sitter_ruby(), queryURLs: [TreeSitterRubyQueries.Query.highlightsFileURL])
            case "php": MacSyntaxLanguage(language: tree_sitter_php(), queryURLs: [TreeSitterPHPQueries.Query.highlightsFileURL])
            case "go": MacSyntaxLanguage(language: tree_sitter_go(), queryURLs: [TreeSitterGoQueries.Query.highlightsFileURL])
            case "rs": MacSyntaxLanguage(language: tree_sitter_rust(), queryURLs: [TreeSitterRustQueries.Query.highlightsFileURL])
            case "java": MacSyntaxLanguage(language: tree_sitter_java(), queryURLs: [TreeSitterJavaQueries.Query.highlightsFileURL])
            case "c": MacSyntaxLanguage(language: tree_sitter_c(), queryURLs: [TreeSitterCQueries.Query.highlightsFileURL])
            case "cpp", "cc", "cxx": MacSyntaxLanguage(language: tree_sitter_cpp(), queryURLs: [TreeSitterCQueries.Query.highlightsFileURL, TreeSitterCPPQueries.Query.highlightsFileURL])
            case "cs": MacSyntaxLanguage(language: tree_sitter_c_sharp(), queryURLs: [TreeSitterCSharpQueries.Query.highlightsFileURL])
            case "sql": MacSyntaxLanguage(language: tree_sitter_sql(), queryURLs: [TreeSitterSQLQueries.Query.highlightsFileURL])
            case "yml", "yaml": MacSyntaxLanguage(language: tree_sitter_yaml(), queryURLs: [TreeSitterYAMLQueries.Query.highlightsFileURL])
            case "toml": MacSyntaxLanguage(language: tree_sitter_toml(), queryURLs: [TreeSitterTOMLQueries.Query.highlightsFileURL])
            case "md", "markdown": MacSyntaxLanguage(language: tree_sitter_markdown(), queryURLs: [TreeSitterMarkdownQueries.Query.highlightsFileURL])
            case "sh", "bash", "zsh": MacSyntaxLanguage(language: tree_sitter_bash(), queryURLs: [TreeSitterBashQueries.Query.highlightsFileURL])
            case "swift": MacSyntaxLanguage(language: tree_sitter_swift(), queryURLs: [TreeSitterSwiftQueries.Query.highlightsFileURL])
            default: nil
            }
        }
    }

    struct MacSyntaxSpan: Sendable {
        let range: NSRange
        let capture: String
    }

    /// Runs a language's highlight queries over a document. Pure and synchronous: callers run it
    /// off the main actor and apply the spans afterwards.
    enum MacSyntaxHighlighter {
        /// Past this the editor stays plain text rather than parsing a huge file on every edit.
        static let maxHighlightedLength = 1_000_000

        static func spans(for text: String, language: MacSyntaxLanguage) -> [MacSyntaxSpan] {
            let utf16 = Array(text.utf16)
            guard !utf16.isEmpty, utf16.count <= maxHighlightedLength,
                  let grammar = language.language,
                  let parser = ts_parser_new()
            else { return [] }
            defer { ts_parser_delete(parser) }
            guard ts_parser_set_language(parser, grammar) else { return [] }

            let tree = utf16.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.flatMap { base in
                    ts_parser_parse_string_encoding(
                        parser, nil,
                        UnsafeRawPointer(base).assumingMemoryBound(to: CChar.self),
                        UInt32(buffer.count * 2),
                        TSInputEncodingUTF16
                    )
                }
            }
            guard let tree else { return [] }
            defer { ts_tree_delete(tree) }

            let source = language.queryURLs
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
            var errorOffset: UInt32 = 0
            var errorType = TSQueryErrorNone
            let query = source.withCString { pointer in
                ts_query_new(grammar, pointer, UInt32(strlen(pointer)), &errorOffset, &errorType)
            }
            guard let query else { return [] }
            defer { ts_query_delete(query) }
            guard let cursor = ts_query_cursor_new() else { return [] }
            defer { ts_query_cursor_delete(cursor) }
            ts_query_cursor_exec(cursor, query, ts_tree_root_node(tree))

            var spans: [MacSyntaxSpan] = []
            var match = TSQueryMatch()
            var captureIndex: UInt32 = 0
            while ts_query_cursor_next_capture(cursor, &match, &captureIndex) {
                let capture = match.captures[Int(captureIndex)]
                var nameLength: UInt32 = 0
                guard let namePointer = ts_query_capture_name_for_id(query, capture.index, &nameLength) else { continue }
                let name = String(
                    decoding: UnsafeRawBufferPointer(start: namePointer, count: Int(nameLength)),
                    as: UTF8.self
                )
                // UTF16 input, so byte offsets are exactly twice the NSString offsets.
                let start = Int(ts_node_start_byte(capture.node)) / 2
                let end = Int(ts_node_end_byte(capture.node)) / 2
                guard end > start else { continue }
                spans.append(MacSyntaxSpan(range: NSRange(location: start, length: end - start), capture: name))
            }
            return spans
        }

        /// Xcode like palette from system colors, so it adapts to light and dark mode.
        static func color(forCapture capture: String) -> NSColor? {
            let root = capture.split(separator: ".").first.map(String.init) ?? capture
            switch root {
            case "keyword", "conditional", "repeat", "include", "exception": return .systemPink
            case "string", "character": return .systemRed
            case "number", "float", "boolean", "constant": return .systemYellow
            case "comment": return .secondaryLabelColor
            case "function", "method", "constructor": return .systemTeal
            case "type", "namespace", "module": return .systemCyan
            case "property", "attribute", "tag", "label", "field": return .systemPurple
            case "escape", "punctuation.special", "operator": return nil
            case "variable" where capture.hasPrefix("variable.builtin"): return .systemPurple
            case "text" where capture.hasPrefix("text.title"): return .systemPink
            case "text" where capture.hasPrefix("text.uri") || capture.hasPrefix("text.reference"): return .systemBlue
            default: return nil
            }
        }
    }
#endif
