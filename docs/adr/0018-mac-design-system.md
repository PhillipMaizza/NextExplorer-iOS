# 0018. The Mac wears the design system over native controls

Status: Accepted

## Context
The Mac app went native in #102: system tables, sheets, alerts, menus and controls, with the
system font. The approved Mac redesign keeps that structure but dresses it like the brand: Inter,
warm surfaces, cards on a chrome background and pill buttons. macOS has one accent colour for
every control and the app sets none, so switches, checkboxes, segments, focus rings and selected
rows are system blue. An orange accent would recolour all of them at once; mixing orange controls
with blue selection is not possible natively.

## Decision
- Structure and behaviour stay native: `Table`, `List(.sidebar)`, `Form`, sheets, `.alert`,
  `.confirmationDialog`, menus, Quick Look.
- Toggle, checkbox, radio, popup, segmented picker, date picker, stepper and slider keep their
  native look and the system blue. The design system adds no styles for them.
- Orange is only on elements the design system draws itself: the primary button, the toolbar
  accent button, progress rings and bars, chips, badges, the logo and avatars.
- The Mac has its own warm colour tokens (`MacChrome`, `MacCard`, `MacRow`, `MacLine`,
  `MacSegment`, `MacField`, `MacChromeText`, `MacChromeSecondary`). iOS keeps its palette.
- `.type()` renders Inter on the Mac at the Mac's text sizes (body 13, callout 12), so density
  stays Mac like. Secondary text uses the warm chrome grey.
- Buttons are pills (`MacDSButtonStyle` over `DSButtonStyle` and `DSButtonSize`), drawn with
  `.radiusLarge` so a 36pt button rounds fully. A destructive role turns a neutral label red.
- The sign in screen and the sidebar account popover stay custom by the owner's choice. Sign in is
  a branded screen: its https and http switch is the DS pill (`DSSegmentedControl` with
  `shouldAlwaysUsePill`) in the Mac colours, and its steps list shows Code only once the server asks
  the account for one. Its large fields are drawn by the design system, so they focus in the accent
  (border and halo) rather than the system blue ring.

Code: `MacColors`, `Typography`, `MacButtonStyles`, `MacFields`, `MacChip`, `MacProgressRing`,
`MacCard`, `MacDialog`, `MacGalleryView`.
