import Testing

@testable import FilesFeature

@Suite
struct MarkdownRendererTests {
    @Test func wrapsOutputInADocumentWithAUTF8Charset() {
        let html = MarkdownRenderer.html(from: "# Title")
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("<h1>Title</h1>"))
    }

    @Test func pullsTheAppFontFromGoogleFontsAndNamesItFirst() {
        let html = MarkdownRenderer.html(from: "# Title")
        #expect(html.contains("fonts.googleapis.com/css2?family=Figtree"))
        #expect(html.contains("font-family: \"Figtree\", -apple-system"))
    }

    @Test func nonASCIIRoundTripsIntactRatherThanMojibake() {
        let html = MarkdownRenderer.html(from: "Docker VM — Stacks")
        #expect(html.contains("Docker VM — Stacks"))
        #expect(!html.contains("â€"))
    }

    @Test func rendersTableCellsAsTextNotALazySequenceDump() {
        let markdown = """
        | Host | Value |
        | ---- | ----- |
        | cpu  | 8     |
        """
        let html = MarkdownRenderer.html(from: markdown)
        #expect(html.contains("<th>Host</th>"))
        #expect(html.contains("<td>cpu</td>"))
        #expect(!html.contains("LazyMapSequence"))
        #expect(!html.contains("MarkupChildren"))
    }
}
