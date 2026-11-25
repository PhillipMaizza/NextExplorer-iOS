# 0021. Space opens an in app peek card instead of the system Quick Look panel

Status: Accepted

## Context
Space on a Mac table row drove the shared system `QLPreviewPanel`. The panel needs a local copy, so every
file came down whole before anything showed, video included, and anything over 100 MB was refused. The
panel could not stream, wear the design system, offer the app's own actions, or show a folder. Driving it
also meant a responder in the window chain and a data source the panel holds unretained.

## Decision
- Space toggles `MacPeekCard` for every row, files and folders alike. Get Info stays on ⌘I. The card is
  drawn by the window (`MacPeekLayer` in `MacMainShell`, fed through the `MacPeekHost` environment object), so
  the scrim dims the whole window evenly, the way the search panel does.
- The card shows each kind with the renderers the app already has: `ImageGalleryPage`, `MediaGalleryPage`
  (streams), `MacInspectorPreview` for text and documents, a fetched `QuickLookPreview` for anything else.
  A folder shows its first items as browse grid tiles from one listing request.
- Nothing is refused. Archives, binaries and files over 100 MB that would come down whole
  (`MacPeekContent.Kind.isFetchedWhole`) show a summary: type icon, kind and size. Media streams, so it has no
  limit, and a copy saved offline always previews.
- The card takes keyboard focus while open: Space and Esc close, ↑↓ move the table selection (the card
  follows), Return opens. The table's Return rename and Delete never reach a file under the scrim, and the
  table takes focus back on close.

Code: `MacPeekCard`, `MacPeekContent`, `MacPeekFolder`, `MacPeekOverlay`, `MacPeekHost`, `MacBrowseTableView`.
