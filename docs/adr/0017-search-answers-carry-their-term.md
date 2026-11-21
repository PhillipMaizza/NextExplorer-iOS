# 0017. Search answers carry their term

Status: Accepted

## Context
Each keystroke starts a debounced search fetch, cancelled in flight by the next one. TCA registers
an effect's cancellation only when its task starts, so under load the fetches of one burst of
typing can start out of order: an earlier term's fetch outlives the typed term's and cancels it,
and its answer was stored as the answer for the term on screen.

## Decision
- Every search response action carries the term it was asked for.
- The reducer drops an answer whose term is not the current `SearchTerm(query).text`. If the
  search is still loading, it asks again for the typed term at once, without the debounce.
- The server's order (names first, closest first, then contents by relevance) is kept as is.

Applies to Browse, Favorites, Spotlight on the Mac and the destination picker. Shared and User
Management filter locally and need none of it.

Code: `BrowseFeature+ReduceSearch`, `FavoritesFeature`, `SpotlightFeature`,
`DestinationPickerFeature`.
