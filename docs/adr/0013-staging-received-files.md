# 0013. Received files are staged before the callback returns

Status: Accepted

## Context
The system deletes a dropped or shared file once the drop closure or item provider callback
returns.

## Decision
- A drop moves the system's temporary copy, or copies the user's original, into a staging folder
  before returning. Upload staging makes its own copy and discards this one; a refused drop
  discards it at once, and the session purge and stale sweep remove any left over.
- The share extension writes its upload envelope inside the provider's callback, and cancelling
  stops the copy itself, not just the wait.

Code: `BrowseDragPayload`, `SharedItemLoader`, `SessionScratchStore`.
