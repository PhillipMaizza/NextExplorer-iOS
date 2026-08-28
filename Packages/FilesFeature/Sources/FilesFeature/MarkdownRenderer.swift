import DesignSystem
import Markdown

/// Converts Markdown to HTML for the "Render Markdown Files" setting — `swift-markdown` only
/// parses to an AST, it doesn't ship an HTML renderer, so this walks the tree itself. The
/// resulting HTML feeds straight into `HTMLRenderedView`, the same component "Render HTML
/// Pages" uses, so relative image references resolve the same way relative CSS/JS does there.
///
/// Deliberately doesn't conform to `MarkupVisitor` — its `visit`/`accept` requirements take
/// `inout Self`, which forces every recursive call site to hold the visitor in a mutable `var`
/// binding, including `self` inside the visitor's own methods (a `let`-bound `self`, which
/// every instance method has). A plain type-switch sidesteps that entirely.
enum MarkdownRenderer {
    static func html(from markdown: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Figtree:ital,wght@0,300..900;1,300..900&display=swap" rel="stylesheet">
        <style>\(documentCSS)</style>
        </head>
        <body>
        \(render(Document(parsing: markdown)))
        </body>
        </html>
        """
    }

    /// Without an explicit charset WebKit guesses Latin-1 for a bare fragment and mangles every
    /// non-ASCII byte (em dashes turn into "\u{00E2}\u{20AC}\u{201D}"). The rest is just enough
    /// to make the page readable in the app's own font (Figtree, pulled from Google Fonts by
    /// the `<link>` in the head — falls back to the system stack offline), with sane width and
    /// visible table borders. `body`'s `font-family` is the lowest-specificity rule in the
    /// document, so a `<style>` block inside the Markdown source still wins the cascade.
    private static let documentCSS = """
    :root { color-scheme: light dark; }
    body {
      font-family: "\(DesignSystemFonts.familyName)", -apple-system, system-ui, sans-serif;
      font-size: 17px; line-height: 1.5; margin: 16px; overflow-wrap: break-word;
    }
    pre { overflow-x: auto; padding: 12px; background: rgba(127,127,127,0.15); border-radius: 6px; }
    code { font-family: ui-monospace, monospace; }
    pre code { background: none; }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    th, td { border: 1px solid rgba(127,127,127,0.4); padding: 6px 10px; text-align: left; }
    blockquote { margin: 0; padding-left: 12px; border-left: 3px solid rgba(127,127,127,0.4); }
    img { max-width: 100%; height: auto; }
    """

    private static func render(_ markup: Markup) -> String {
        switch markup {
        case let node as Paragraph: return "<p>\(renderChildren(node))</p>\n"
        case let node as Heading: return "<h\(node.level)>\(renderChildren(node))</h\(node.level)>\n"
        case let node as Text: return escaped(node.string)
        case let node as Emphasis: return "<em>\(renderChildren(node))</em>"
        case let node as Strong: return "<strong>\(renderChildren(node))</strong>"
        case let node as Strikethrough: return "<del>\(renderChildren(node))</del>"
        case let node as InlineCode: return "<code>\(escaped(node.code))</code>"
        case let node as CodeBlock:
            let languageClass = node.language.map { " class=\"language-\(escapedAttribute($0))\"" } ?? ""
            return "<pre><code\(languageClass)>\(escaped(node.code))</code></pre>\n"
        case let node as BlockQuote: return "<blockquote>\(renderChildren(node))</blockquote>\n"
        case let node as Link:
            let destination = node.destination.map { " href=\"\(escapedAttribute($0))\"" } ?? ""
            return "<a\(destination)>\(renderChildren(node))</a>"
        case let node as Image:
            let source = escapedAttribute(node.source ?? "")
            let alt = escapedAttribute(renderChildren(node))
            return "<img src=\"\(source)\" alt=\"\(alt)\">"
        case is LineBreak: return "<br>\n"
        case is SoftBreak: return "\n"
        case is ThematicBreak: return "<hr>\n"
        case let node as UnorderedList: return "<ul>\n\(renderChildren(node))</ul>\n"
        case let node as OrderedList: return "<ol>\n\(renderChildren(node))</ol>\n"
        case let node as ListItem: return "<li>\(renderChildren(node))</li>\n"
        case let node as Table: return "<table>\n\(renderChildren(node))</table>\n"
        case let node as Table.Head:
            let cells = Array(node.cells).map { "<th>\(render($0))</th>" }.joined()
            return "<thead><tr>\(cells)</tr></thead>\n"
        case let node as Table.Body: return "<tbody>\n\(renderChildren(node))</tbody>\n"
        case let node as Table.Row:
            let cells = Array(node.cells).map { "<td>\(render($0))</td>" }.joined()
            return "<tr>\(cells)</tr>\n"
        case let node as HTMLBlock: return node.rawHTML
        case let node as InlineHTML: return node.rawHTML
        default: return renderChildren(markup)
        }
    }

    private static func renderChildren(_ markup: Markup) -> String {
        markup.children.map { render($0) }.joined()
    }

    private static func escaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedAttribute(_ string: String) -> String {
        escaped(string).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
