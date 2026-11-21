# 0007. Server rules are mirrored, never replaced

Status: Accepted

## Context
The upstream server is the source of truth. Checking obviously bad input on the device saves a
round trip and gives a readable message, but must never disagree with the server.

## Decision
- Client checks mirror named server code and the server stays the final authority:
  - `FileNameRule` mirrors `ensureValidName` (`backend/src/utils/pathUtils.js`).
  - `CredentialRules` mirrors the password length check in `services/users/localAuth.js`; the
    email shape check is a UX nicety the server does not make.
  - `EditableTextFiles` mirrors the web client's editor list plus the server's
    `EDITOR_EXTENSIONS`; new files are limited to these.
  - `SearchTerm` mirrors `GET /api/search`: trimmed, `MIN_TERM_LENGTH` counted in UTF16 units, a
    two character term sent as `*term*`, `*` and `?` as name shapes, names compared in NFC.
  - `DeleteImpact` models only the counts `POST /api/files/delete-impact` returns, as the web
    client shows only how many links are affected.
- Server errors are read in all three shapes the server sends: `{ error: { message } }`,
  `{ error: "..." }` and `{ message }`.

## Consequences
A value that passes here can still be refused (a duplicate, a permission). A server change to
one of these rules needs the mirror updated in the same release.

Code: `FileNameRule`, `CredentialRules`, `EditableTextFiles`, `SearchTerm`, `DeleteImpact`,
`FilesService.errorMessage(from:)`.
