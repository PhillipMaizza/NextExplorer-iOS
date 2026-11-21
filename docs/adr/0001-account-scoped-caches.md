# 0001. Every cache is scoped to one account

Status: Accepted

## Context
Several accounts can be signed in at once, on different servers or as two users on one server.
A cache entry read under the wrong account shows one person's files to another.

## Decision
- `CacheAccountScope` holds the active account's scope process wide. `AppFeature` sets it when a
  session begins or the active account changes and empties it on full teardown.
- Every disk cache folds the scope into its key (`CacheLayout.key`): directory listings, JSON
  lists, previews, thumbnails, rendered PDF pages. Switching accounts reads the other account's
  entries; nothing is wiped and both survive.
- Async work binds a store to the scope it started under (`bound(to:)`), so a late answer writes
  the namespace that was active when it was asked.
- Saved downloads use `DownloadAccountScope`: a hash of server URL and user id as the folder name.
- `URLCache` is off. The app's own caches are cleared at every session boundary; the shared URL
  cache is not and would outlive the account.
- Entries written by releases before scoping carry no prefix, so no account wipe reaches them.
  `LegacyCacheCleanup` removes them once, using the names in `CacheLayout`.

- `RebuildableCaches.clearAll()` empties every store the server can refill (listings, saved lists,
  previews, decoded and upload thumbnails, editor ETags) at fresh sign in, teardown and Clear
  Cache, off main inside the effect. Offline pins and downloads are the user's files; callers
  that also drop those do it themselves.

## Consequences
An empty scope is the legacy unscoped namespace; tests that never set a scope use it. Wipe stamps
on account boundaries (`markEveryAccountWiped`) make in flight downloads of the old account fail
rather than land.

Code: `CacheAccountScope`, `CacheLayout`, `DownloadAccountScope`, `LegacyCacheCleanup`,
`RebuildableCaches`, `NetworkClient+Live`.
