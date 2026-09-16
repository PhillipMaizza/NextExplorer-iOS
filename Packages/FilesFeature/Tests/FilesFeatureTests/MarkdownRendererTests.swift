@testable import FilesFeature
import Testing

struct MarkdownRendererTests {
    @Test func wrapsOutputInADocumentWithAUTF8Charset() {
        let html = MarkdownRenderer.html(from: "# Title")
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("<h1>Title</h1>"))
    }

    @Test func namesTheAppFontFirstWithoutAnyRemoteFontFetch() {
        let html = MarkdownRenderer.html(from: "# Title")
        #expect(html.contains("font-family: \"Figtree\", -apple-system"))
        // The render path must not phone home: no remote stylesheet, no preconnect.
        #expect(!html.contains("fonts.googleapis.com"))
        #expect(!html.contains("fonts.gstatic.com"))
        #expect(!html.contains("<link"))
    }

    @Test func stripsActiveContentFromEmbeddedRawHTML() {
        let html = MarkdownRenderer.html(from: "<script>alert(1)</script><p onclick=\"x()\">hi</p>")
        #expect(!html.contains("<script"))
        #expect(!html.contains("onclick"))
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
