# 0025. An encrypted zip asks for its password in the app's alert

Status: Accepted

## Context
`POST /api/files/zip/extract` streams an `error` event with `code` `ARCHIVE_PASSWORD_REQUIRED` when an
encrypted zip comes without a password, and `ARCHIVE_INVALID_PASSWORD` when the one sent is wrong. The
app read only the message, so an encrypted zip failed with a generic error and could not be extracted.
The web asks in a dialog that stays open and busy while the retry runs.

## Decision
- The Mac shows `MacAlertSheet` with a blue lock tile, the web's copy, a secure field and Extract / Cancel.
  Extract stays disabled while the field is empty; Return in the field extracts.
- Extract retries with `password` in the body. The alert stays open with a spinner on Extract while it runs,
  as the web's dialog does; the progress toast shows meanwhile.
- A wrong password keeps the alert open, clears the field, rings it red and shows the web's line under it.
  `invalidAttempts` counts, so a second wrong try clears the field again.
- Cancel closes the alert and leaves the archive untouched. Any other failure closes it and shows the
  error as before.
- Whole zip extract only, both into a new folder and into the current one. Picking entries through
  `POST /api/archive/extract` stays refused by the server for encrypted entries.
- iOS keeps the error text (the protected archive message) until it gets the prompt.
- The lock tile is only for this alert; the icon for the other alerts is still the owner's pick.

Code: `FilesService.ArchivePasswordCode`, `BrowseFeature.ArchivePasswordPrompt`,
`MacArchivePasswordAlert`, `BrowseDeleteAndArchiveTests.protectedZipAsksForItsPasswordUntilItIsRight`.
