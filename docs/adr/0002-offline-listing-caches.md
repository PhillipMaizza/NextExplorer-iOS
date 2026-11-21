# 0002. Listings are cached on disk, best effort

Status: Accepted

## Context
Browsing must keep working offline, and a cache must never be the reason browsing fails.

## Decision
- Directory listings (`DirectoryCacheStore`) are one JSON file per server and path, revalidated
  with the strong `ETag` (stale while revalidate). Lists without a directory of their own
  (Favorites, Shared) use `JSONCacheStore` and are read only when the request fails `.offline`.
- Every operation is best effort: a miss, a failed write or a corrupt entry is swallowed and the
  caller falls back to the network. Nothing throws.
- Entries live in Application Support, not Caches, which the system purges exactly when an
  offline user needs them. Both stores cap size and count and evict the oldest writes, and are
  encrypted at rest and excluded from backup.
- A `304` only touches the freshness stamp, and only when the stored tag still equals the one the
  request sent (compare and set), so a late `304` never overwrites a newer listing.
- One listing is capped at about 2 MB (roughly 12k entries) so `read` stays a cheap synchronous
  decode; an item count check runs first so a huge listing is not encoded just to be rejected.
  A folder over the cap drops its earlier copy rather than keep a stale one.
- Conditional browse requests use `.reloadIgnoringLocalCacheData` so the URL cache never answers
  for the app's own cache.

## Consequences
`DirectoryCacheStore` serialises disk access with a lock (the work is KB scale), `JSONCacheStore`
with one serial queue so writes return at once and reads see them.

Code: `DirectoryCacheStore`, `JSONCacheStore`, `FilesService+Browse`.
