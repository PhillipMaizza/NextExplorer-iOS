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
        render(Document(parsing: markdown))
    }

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
            let cells = node.cells.map { "<th>\(render($0))</th>" }.joined()
            return "<thead><tr>\(cells)</tr></thead>\n"
        case let node as Table.Body: return "<tbody>\n\(renderChildren(node))</tbody>\n"
        case let node as Table.Row:
            let cells = node.cells.map { "<td>\(render($0))</td>" }.joined()
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
