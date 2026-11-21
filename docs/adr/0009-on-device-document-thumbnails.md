# 0009. Document thumbnails are drawn on device

Status: Accepted

## Context
The server makes thumbnails only for pictures and videos (`backend/src/routes/thumbnails.js`).
Decoding full size images keeps them resident and gets older devices killed for memory.

## Decision
- A document's first page is drawn on device from a downloaded copy: PDFKit for PDFs, Quick Look
  `.thumbnail` for the rest, laid on white because the render cache is JPEG. Renders sit under
  the shared preview cache root, so Clear Cache covers them.
- PDF rasterisation runs one at a time in an actor with no `await` inside: PDFKit is not safe
  to drive concurrently, and one at a time keeps a folder of PDFs from pegging every core.
  Downloads stay parallel on their own capped session.
- Pages render at an exact pixel size with the CoreGraphics renderer the share extension uses,
  not `PDFPage.thumbnail(of:for:)`, which renders at screen scale (9x the area on a 3x device).
- Images decode through ImageIO's thumbnail path to the pixel size on screen
  (`pointSize * displayScale`), never `UIImage(data:)` or `AsyncImage`.
- The preview and download cache is capped at 512 MB, since Caches is only purged under severe
  storage pressure.

Code: `DocumentThumbnailCache`, `DocumentThumbnailStore`, `ImageDownsampling`,
`FilesService+PreviewCache`.
