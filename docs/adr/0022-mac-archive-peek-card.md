# 0022. Archives open in a peek card read through the server's archive routes

Status: Accepted

## Context
On the Mac an archive opened in a sheet that downloaded the whole file and read it with the bundled zip and
rar readers. Nothing showed until the download finished, only zip and rar opened, and Go ▸ Back never reached
the sheet: a focused value set inside a sheet does not reach the main menu. The server now lists, streams
and extracts inside every archive its tools read (`/api/archive/list`, `/entry`, `/extract`) and names those
formats in `features.archives.extensions`.

## Decision
- An archive opens in `ArchivePeekCard`, drawn in the window by `MacPeekHost` like the Space peek card, so
  its ⌘[ and arrow keys reach `MacCommands`. Folders show as grid tiles. A file opens on a stage with ‹ ›
  and a strip of its sibling files. Crumbs name the archive, each folder and the open file. ⌘[ at the top
  closes the card and never moves the browser behind it.
- One reducer, `ArchiveBrowserFeature`, has two sources. When the server lists the archive's extension
  it reads one level and one entry at a time through the archive routes. Otherwise (an older server) it
  downloads the archive once and reads it on the Mac through `ArchiveReaderClient`.
- An entry comes down only when it is opened, into the session scratch folder. Image tiles get thumbnails
  from zip archives only. A solid archive (7z, rar) makes the server unpack the whole archive for every
  entry it reads.
- Extract shows only with the server source. At the top it takes the whole archive through
  `/files/zip/extract`, which makes a folder (the web client's behaviour). Inside a folder, or with a file
  open, it takes that folder or file through `/archive/extract`, which places it next to the archive.
  Browse runs the extraction, so progress, errors, selection and other windows behave as they do for
  every file action.
- Browse saves the server's archive list (`ListCache`) so pushed folders, folder windows and Favorites
  know it without asking.
- iOS keeps `ArchiveBrowserView`.

Code: `ArchiveBrowserFeature`, `ArchiveReaderClient`, `ArchiveThumbnailLoader`, `ArchivePeekCard`,
`ArchivePeekGrid`, `ArchivePeekStage`, `ArchivePeekPresenter`, `FilesService+Archive`.
