# 0011. Tab icons are static artwork

Status: Accepted

## Context
On the iOS 26 and later tab bar, `Tab(value:)` renders every icon filled whatever symbol variant
is passed, so the outline and filled swap by selection does not happen (verified on device).

## Decision
Tab icons are vector artwork exported from Symbols.app (template rendering, single scale), and
`MainTabView` picks the outline or filled image by selection itself.

Code: `IconKit` tab images, `MainTabView`.
