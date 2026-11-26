# 0019. The Mac wears the design system over native controls

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
  (36pt, field fill, hairline, accent focus border, halo and caret, like the sign in fields) and
  `MacPopup` (a `Menu` over an inline `Picker`, 32pt, muted up and down chevron), so VoiceOver and
  the keyboard keep the menu. Both dim when disabled.
- Status chips use tones (`MacChip.Tone`: green, red, gray) with their own text and fill tokens
  (`MacTag*`), the canvas pills, rather than a tinted wash of the accent palette.
- Settings panes that follow the canvas are a `MacFormPage` of `MacFormGroup`s and `MacFormRow`s:
  rounded `MacRow` groups with hairlines between rows, 52pt rows, inset 40 from the card edge.
  The system grouped `Form` cannot be widened to the card or hold a zebra table, so the canvas
  panes leave it. The Settings window is the canvas width, 1200 by 620, with a 272 sidebar.
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
- Every field the design system draws, plain or secure, focuses in the accent, caret included. The
  system leaves a secure field's caret blue, so `MacSecureField` tints its field editor directly.
- Form sheets follow the canvas dialogs: a larger title, labels without colons, full width popups,
  and a `MacSegmentedPicker` whose chosen option fills in the accent (the canvas shows the system
  blue, which the app has no other use for).
- Confirmations the canvas draws as alerts are `MacAlertSheet`s: the app mark, the question, the
  message centred, then the full width confirm over Cancel (Esc). Return confirms nothing, so a
  destructive choice is never one keypress away.
  Every confirmation goes through `dsAlert`, which shows this sheet on the Mac and closes it after
  the chosen button, as a system alert would; while the confirm action runs, its spinner locks
  the buttons. The quit prompt with transfers running stays an `NSAlert`: it answers
  `applicationShouldTerminate`, where no window is sure to be open to hold a sheet.
- A pane's save and discard buttons sit in its header, not in a bar under the form. Notes under a
  group are one `MacFormFootnote`. In an excluded paths list a removed path stays, struck through
  with Add beside it, until the pane is saved, so a removal can be taken back before it reaches
  the server.
- File lists (Browse, Favorites, Offline, Trash, Shared, search results) are one native `Table`
  look, by the owner's choice: the system header with sortable columns, system blue selection,
  native separators and no zebra stripes, 48pt rows and 32pt tiles. Row height comes from the cell
  content (`macBoardTableCell`), never from the table's `rowHeight` or `style`: SwiftUI resets
  both on updates, and restyling it back redraws the whole table on every click.
- The share inspector follows the file inspector's kit, by the owner's choice: the file's own
  preview (or its tile), a title that turns into a field on click to rename the share, then the
  share link in a selectable field with its copy button inside. The direct download link sits
  behind a disclosure under it, with its mode (Open in browser, Download, Raw) picked right there,
  because the mode only shapes the copied URL and never changes the share; it is offered only for
  a public share without a password, where the server serves the file without the share page. Then
  Downloads, Last opened and Shared tiles, Shared With (Change or Limit open the audience popover),
  and Access, where Permission saves from its menu and Password and Expires open their own
  popovers; an expired share is read only until it gets a new date. Delete Link stays pinned at
  the bottom. The Shared table is flat unless an item has several shares, so its names line up
  with Browse; an outline always reserves the disclosure gap.
- Dialog motion: anything a dialog shows or hides as its state changes (errors, field errors,
  spinners, loaded content, success notes, a form giving way to its result) fades with
  `DSMotion.stateFade` through `macDialogReveal()`, a transition that carries its own animation, so
  changes that arrive from reducer effects animate without wrapping the send. The fade is the same
  in and out. Selection that moves (icon wells, swatches, segmented pills) slides with
  `DSMotion.controlMorph`; the success badge pops in with `DSMotion.pop`. No move or scale on
  anything that changes the sheet's height, because the sheet window resizes in one step. For the
  same reason a swap that changes the sheet's height by more than a line (a loading spinner giving
  way to the loaded form, a form giving way to its result) stays instant: faded, the taller state
  draws clipped inside the old window until it snaps. Swaps inside a box of fixed height (the
  destination picker, folder browsers) crossfade in place in a `ZStack`, never stacked.
- Text size: macOS gives apps no Dynamic Type (`dynamicTypeSize`, `Font.custom(relativeTo:)` and
  `@ScaledMetric` all render the same on the Mac), so the design system owns one scale, the
  `macTextScale` environment value, clamped to 1 through 1.4. `.type()` reads it on the Mac; text of
  32pt or more stops growing at 32pt so titles do not take over a pane. The app sets no scale and offers
  no setting today; the design system is ready for one.
- Controls that hold text take their height from one ladder, `MacControlHeight` (22, 28, 32, 36, 40,
  44, 48 and the 52pt form row), as a minimum that grows with the text scale (`macMinHeight`), never as
  a fixed `frame(height:)` that would clip larger text. Glyphs beside text scale with it (`macSquare`).
- Mac colour tokens carry Increase Contrast variants (`MacLine`, `MacChromeSecondary`,
  `MacChromeTertiary`, the `MacTag*` text colours), so field and group edges reach 3:1 and secondary
  text gets darker when the system asks for more contrast. Tertiary text is its own colour that keeps
  4.5:1 on chrome, card and row surfaces; the dimmer 60% tone is only for disabled text
  (`TextStyle.disabled`).
- A focused field's border is drawn in `accentText`, which keeps 3:1 on the white card in light mode
  where the brand accent does not; the soft halo around it stays in the accent.
- A list row that selects on click and opens on double click uses `macSelectable`, which also makes it
  reachable with Full Keyboard Access (Space selects, Return opens) and gives VoiceOver the same two
  actions.
- Dialog forms lay out `MacFormSheetRow`s (label column, controls stacked beside it, notes as
  `MacControlNote`) inside `MacFormSheet`'s columns form; Settings panes keep `MacFormRow` in grouped
  rows. Both live in the design system.

Code: `MacColors`, `Typography`, `MacButtonStyles`, `MacFields`, `MacChip`, `MacProgressRing`,
`MacCard`, `MacDialog`, `MacGalleryView`, `MacSidebarRow`, `MacSettingsRoot`, `MacFormControls`,
`MacFormLayout`, `MacSwitchToggleStyle`, `MacSegmentedPicker`, `MacAlertSheet`, `MacScale`.
