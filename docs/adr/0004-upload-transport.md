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
- Files under `UploadMode.largeFileBytes` (8 MiB) go direct. Larger files use TUS
  (`/api/upload/tus`) when the admin forces chunks, or after a direct request is refused for its
  size with auto fallback on. A piece that fails in transit resumes from the server's offset; an
  upload the server forgot restarts once.

## Consequences
Known limits are tracked as issues #216 (small files ignore forced chunking), #217 (upload id
not persisted across launches) and #218 (no stall watchdog or 413 step down).

Code: `FilesService+PreviewCache.uploadFile`, `FilesService+TusUpload`, `UploadMode`.
