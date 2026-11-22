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
- Checkbox, radio, segmented picker, date picker, stepper and slider keep their native look and
  the system blue. Switches keep the native control but take the accent tint (`.macSwitch`), by
  the owner's choice; the tint is scoped to the switch so pickers beside it stay neutral.
- Settings fields and popups are drawn by the design system to match the canvas: `MacTextField`
  (34pt, field fill, hairline, system accent focus ring and halo) and `MacPopup` (a `Menu` over an
  inline `Picker`, 32pt, muted up and down chevron), so VoiceOver and the keyboard keep the menu.
- Status chips use tones (`MacChip.Tone`: green, red, gray) with their own text and fill tokens
  (`MacTag*`), the canvas pills, rather than a tinted wash of the accent palette.
- Settings panes that follow the canvas are a `MacFormPage` of `MacFormGroup`s and `MacFormRow`s:
  rounded `MacRow` groups with hairlines between rows, 52pt rows, inset 40 from the card edge.
  The system grouped `Form` cannot be widened to the card or hold a zebra table, so the canvas
  panes leave it. The Settings window is the canvas size, 1200 by 780, with a 272 sidebar.
- Orange is only on elements the design system draws itself: the primary button, the toolbar
  accent button, progress rings and bars, chips, badges, the logo, avatars and the selected
  sidebar row's glyph.
- Sidebar rows (main window and Settings) are drawn by the design system inside a plain list, by
  the owner's choice: the selected row is a `MacSelection` pill (white in light, a soft wash in
  dark) with a semibold title and an accent glyph, and hover is a `MacChromeHover` wash. The
  Settings sidebar is a fixed column beside the pane card rather than a split view, so it sits on
  the chrome without the system sidebar material or divider.
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
`MacCard`, `MacDialog`, `MacGalleryView`, `MacSidebarRow`, `MacSettingsRoot`, `MacFormControls`,
`MacFormLayout`, `MacSwitchToggleStyle`.
