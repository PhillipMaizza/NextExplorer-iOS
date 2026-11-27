# 0027. Downloading files and folders together asks One Archive or Separate Files

Status: Accepted

## Context
A Mac multi selection download asks for a folder once, then saves files as they are and folders as real folder
trees. There was no way to get one zip of the selection, which the web gives by default (`POST /api/download`).
The web's other path, `POST /api/download/plan`, keeps loose files but zips every folder together.

## Decision
- A selection that mixes files and folders asks "Download N items as" with One Archive (default), Separate Files
  and Cancel.
- One Archive: a save panel named after the folder on screen (`<title>.zip`), then one `POST /api/download`
  with `items` and the folder as `basePath`, streamed by the download queue as a single row.
- Separate Files keeps today's behaviour: one folder picker, files as they are, folders as real folder trees.
  The plan route is not used, since it would turn folders back into a zip (owner call, 27 Nov).
- Only files or only folders skip the question and download separately, as before.

Code: `BrowseFeature.BulkDownloadChoice`, `BrowseFeature.startArchiveDownload`, `DownloadSaveRequest.archiveOf`,
`FilesClient.downloadArchive`, `MacDownloadChoiceTests`.
