# 0026. Versions in the item menu, Show All Versions in the inspector

Status: Accepted

## Context
A file's versions were reachable only from the inspector's Versions section. The web offers Versions in the
item menu for a single file when `GET /api/features` says `versions.enabled` and a share does not hide them.
SwiftUI menus cannot change while open, so a submenu needs its data before it opens.

## Decision
- The table and grid item menu (after Get Info) and the inspector's More menu get a Versions submenu, laid out
  like File ▸ Revert To: up to the five newest earlier versions (label, else date), each with Restore…,
  Download… and Save as Copy by the history's rights, then Show All Versions….
- Shown for one file when the server keeps versions (`ServerFeatures.isVersionsEnabled`, read once per server)
  and the history's `canSee` is not false. Hidden for folders and device content, like Get Info.
- `MacVersionsModel` moves from the inspector to `MacBrowsePanels` and keeps one history per file, cleared when
  the server changes. It loads the inspector's file, or the single selected file when the inspector is closed,
  after the inspector's settle delay, and shows a remembered history at once while it reloads.
- A row never loaded (a right click on an unselected row) shows a disabled Loading… row. Menu code never starts
  a fetch.
- Changes started from the menu name their file, so a right click on another row never touches the selected
  file's history. Their failures go to the window's toast; the inspector's own stay under its section.
- Show All Versions… opens the inspector on the file, scrolls to Versions once its history is there, and rings
  the section with the accent for a second.
- The menu bar's File menu gets no Versions: it is not an item menu. Favorites hold only folders, so their
  inspector has no versions model.

Code: `MacVersionsModel.menuPhase(for:)`, `MacVersionsMenu`, `MacBrowsePanels`,
`MacInspectorVersionsSection.anchor`, `MacVersionsMenuTests`.
