# 0020. The inspector's More menu shows shortcuts it does not own, and Back closes the inspector first

Status: Accepted

## Context
The inspector's More menu must show the same shortcut reminders as the board (Duplicate ⌘D, Rename ↵,
Move to Trash ⌘⌫). A native `Menu` only shows a reminder when the item binds the key, and a bound key in
that menu would fire from the file list and act on the inspected item instead of the selection.

Going Back with the inspector open used to carry it onto the folder just left, even when the folder
returned to never had it open, so the panel jumped between screens.

## Decision
- The More menu is a design system panel (`MacActionMenuPanel`) in a popover. Its rows draw the
  shortcut as text; the keys stay owned by the menu bar commands, which act on the selection.
- Open With keeps a native submenu inside that panel, since it lists apps with their icons.
- The tab remembers each folder the inspector was open on when a deeper folder opened
  (`inspectorLeftOpenPaths`). Back to such a folder keeps the inspector and selects the folder just
  left. Back anywhere else fades the inspector out first (`DSMotion.quickFade`), then pops.

Code: `MacActionMenu`, `MacInspectorMoreMenu`, `MacInspectorQuickActions`, `BrowseTabFeature`.
