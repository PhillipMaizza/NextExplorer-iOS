# 0008. Rendered HTML runs no script and reaches no network

Status: Accepted

## Context
HTML and Markdown files come from the user's server or from archives; their content is untrusted.

## Decision
- JavaScript is disabled in every rendered page's configuration.
- A content rule list blocks every load that is not a local file or inline data. The navigation
  delegate only sees page navigations, so images, stylesheets and fonts would otherwise reach
  the network and tell a stranger the reader's address and when the file was opened.
- Same folder assets are fetched first (from the server or the open archive) and written beside
  the page; the page loads with `loadFileURL`, which resolves relative paths against its
  neighbours. Root absolute references are placed relative to the file's own folder.
- Every relative path joins under the base directory only if the standardised result stays inside
  it, so `..` in an archive entry or an `src` cannot write outside the sandbox folder.
- The page file is always written as `.html`: WebKit infers the MIME type from the extension,
  and a converted `README.md` showed its HTML source as text.
- Markdown converts to HTML with a type switch over the `swift-markdown` tree rather than
  `MarkupVisitor`, whose `inout Self` requirements force every recursive call through a `var`.

Code: `HTMLRenderedView`, `MarkdownRenderer`.
