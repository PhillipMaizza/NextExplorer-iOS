# 0024. Browse cancel ids are keyed by the screen's folder

Status: Accepted

## Context
The Browse tab hosts its root screen with `Scope` and every opened folder in a `StackState` of the same
`BrowseFeature`. The Composable Architecture files each stack element's effect under every prefix of its navigation
path, the empty one included, so a root effect started with `cancelInFlight` cancels the effect with the
same id on every pushed screen. After a paste, undo, restore or app activation the tab refreshes the
root and every pushed folder together; whenever the folder's fetch started first, the root's load
cancelled it and the folder kept showing the old listing until a manual refresh.

## Decision
- Every `BrowseFeature` effect id is `ScreenCancelID(directoryPath:id:)`, built with
  `state.cancelID(_:)`, so screens of different folders never cancel each other.
- A screen's `directoryPath` is fixed at creation, so ids stay stable for its whole life.
- Favorites and Offline host `BrowseFeature` only as stack or presentation siblings, which do not share a
  path prefix; they need nothing more.

Code: `BrowseFeature.ScreenCancelID`, `BrowseFeature.State.cancelID(_:)`,
`BrowseTabFeatureTests.rootRefreshLeavesAPushedListingRunning`.
