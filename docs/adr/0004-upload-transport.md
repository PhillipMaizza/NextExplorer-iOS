# 0004. Uploads go direct, then resumable when refused

Status: Accepted

## Context
Most servers take a plain multipart upload. Some sit behind a proxy that refuses large bodies,
and the admin can force chunked uploads.

## Decision
- `POST /api/upload` sends one `multipart/form-data` request per file. The text fields
  (`uploadTo`, `relativePath`) must precede `filedata`: the server's multer storage reads
  `req.body` inside `_handleFile`, so a file part first sees an empty body. The server rejects
  the root as a destination and auto renames on collision.
- The request is written to a temporary multipart envelope on disk and streamed from it, so a
  large file never sits in memory.
- The server's `uploads` settings are read once per server for the life of the client and again
  after any refusal for size. Forced chunking sends every file as TUS pieces, as the web client
  does. Otherwise a file goes direct, or as pieces of the size this origin taught the app after a
  refusal (auto fallback).
- A TUS upload's URL is remembered per account, server, destination, name and a fingerprint of
  the file (its size plus the first and last MiB), so an upload cut off by the app ending resumes
  from the server's offset. It is forgotten on success, on cancel, on any failure that is not
  a lost connection, and at every account boundary (`RebuildableCaches.clearAll()`).
- A piece that fails in transit, times out (the 300 s inactivity budget of an upload) or meets a
  retryable 5xx resumes from the offset the server reports, three times at most. A piece refused
  with 413 is sent again at the next smaller rung of the fallback ladder. An upload the server
  forgot restarts once.

Verified against the upstream server in Docker: a 400 MB upload killed at 56% resumed at the
server's offset with identical bytes; behind nginx with a 10 MB body limit a 16 MiB piece got 413
and the upload finished in 8 MiB pieces; a 4 KB file went through TUS when chunking was forced.
The server sets no TUS piece limit of its own, so a 413 on a piece comes from a proxy.

Code: `FilesService+PreviewCache.uploadFile`, `FilesService+TusUpload`, `TusResumeMemory`,
`UploadSettingsMemo`, `UploadMode`.
