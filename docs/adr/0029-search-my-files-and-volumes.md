# 0029. Search Everywhere from My Files shows My Files and Volumes as two sections

Status: Accepted

## Context
`GET /api/search?path=` searches the volumes and leaves personal folders out by design. Everywhere from inside
My Files sent only that request, so nothing from My Files came back.

## Decision
- On the Mac, Everywhere from My Files or any folder below it sends two requests at once:
  `path=personal` (the My Files section) and `path=` (the Volumes section). Everywhere from anywhere else stays
  one request. The iPhone keeps one request.
- Each section has its own count, Show More (own limit step) and failure line with Retry. Answers are never
  merged into one order. Retry asks both sections again.
- The My Files section is the existing search lane: instant matches, saved listings offline, the footer and its
  failure handling carry over. The footer's Show More moves into the My Files header in this mode.
- A volumes answer of 403, 404 or offline means the account has no volumes to search: the section is simply
  absent. Any other failure shows in the section header. A section with no hits shows no header.
- Results kept on this device lead inside each section; the On device / Remote headers are not shown in this
  mode, since table sections cannot nest.
- One table holds both sections, so arrow keys cross them, and the kind chips filter and count both.
- Out of scope: "In other folders" from a My Files subfolder still searches the volumes only; its Show all
  results everywhere button switches to this two section search.

Code: `BrowseFeature.VolumeSearch`, `isSearchingMyFilesAndVolumes`, `fetchSearchLanes`, `MacSearchLane`,
`SearchMyFilesAndVolumesTests`.
