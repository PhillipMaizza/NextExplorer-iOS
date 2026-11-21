# 0010. One split view per tab

Status: Accepted

## Context
Hosting a path bound `NavigationStack` (TCA `StackState`) in a split view detail, then replacing
it with another section's stack, traps in `NavigationColumnState.boundPathChange` on the switch.
On the Mac, one split view with `.id` on the swapped detail still traps.

## Decision
Each tab gets its own `NavigationSplitView`; each `switch` branch is a distinct type, so changing
tab tears the split view down and builds the next one fresh. The shared `MainTabSidebar` and
`columnVisibility` keep the sidebar identical across tabs, and store state lives outside the view
tree, so nothing is lost.

Code: `MainTabView.splitView`.
