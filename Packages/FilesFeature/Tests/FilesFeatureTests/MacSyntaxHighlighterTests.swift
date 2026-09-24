#if os(macOS)
    @testable import FilesFeature
    import Foundation
    import Testing

    struct MacSyntaxHighlighterTests {
        @Test
        func swiftSourceGetsKeywordAndStringSpans() throws {
            let source = "let greeting = \"hi\""
            let language = try #require(MacSyntaxLanguage.forKind("swift"))

            let spans = MacSyntaxHighlighter.spans(for: source, language: language)
            let text = source as NSString

            #expect(spans.contains { $0.capture.hasPrefix("keyword") && text.substring(with: $0.range) == "let" })
            #expect(spans.contains { $0.capture.hasPrefix("string") && text.substring(with: $0.range).contains("hi") })
        }

        @Test
        func typeScriptLayersOverJavaScriptQueries() throws {
            let language = try #require(MacSyntaxLanguage.forKind("ts"))
            #expect(language.queryURLs.count == 2)
            #expect(!MacSyntaxHighlighter.spans(for: "const n: number = 1", language: language).isEmpty)
        }

        @Test
        func unknownKindsStayPlainText() {
            #expect(MacSyntaxLanguage.forKind("dat") == nil)
        }

        @Test
        func oversizedDocumentsAreNotParsed() throws {
            let language = try #require(MacSyntaxLanguage.forKind("json"))
            let huge = String(repeating: "1", count: MacSyntaxHighlighter.maxHighlightedLength + 1)
            #expect(MacSyntaxHighlighter.spans(for: huge, language: language).isEmpty)
        }
    }
#endif
