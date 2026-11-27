# Architecture decision records

A decision that the code cannot show on its own lives here, not in a code comment. Each record
says what was decided, why, and what it costs, and names the code it governs.

Add a record when a choice is non obvious, crosses files, or would be undone by a reasonable
refactor. Number it after the last one and keep it short. A record that stops holding is marked
`Superseded by NNNN` rather than deleted.

| # | Decision |
|---|----------|
| [0001](0001-account-scoped-caches.md) | Every cache is scoped to one account |
| [0002](0002-offline-listing-caches.md) | Listings are cached on disk, best effort |
| [0003](0003-network-sessions-and-timeouts.md) | Separate URL sessions per kind of traffic |
| [0004](0004-upload-transport.md) | Uploads go direct, then resumable when refused |
| [0005](0005-keychain-this-device-only.md) | Secrets never leave the device |
| [0006](0006-multi-account-session-cookies.md) | One active cookie, many stored accounts |
| [0007](0007-server-rules-mirrored-client-side.md) | Server rules are mirrored, never replaced |
| [0008](0008-untrusted-html-rendering.md) | Rendered HTML runs no script and reaches no network |
| [0009](0009-on-device-document-thumbnails.md) | Document thumbnails are drawn on device |
| [0010](0010-one-split-view-per-tab.md) | One split view per tab |
| [0011](0011-tab-icons-as-static-artwork.md) | Tab icons are static artwork |
| [0012](0012-inter-weights-on-the-variation-axis.md) | Inter weights are set on the variation axis |
| [0013](0013-staging-received-files.md) | Received files are staged before the callback returns |
| [0014](0014-mac-ui-tests-type-on-abc.md) | Mac UI tests type on the ABC layout |
| [0015](0015-fixed-beat-polling.md) | Polling runs on fixed beats |
| [0016](0016-code-comments-ratchet.md) | Code carries no comments; a ratchet holds the rest |
| [0017](0017-search-answers-carry-their-term.md) | Search answers carry their term |
| [0018](0018-unlock-is-not-a-fresh-sign-in.md) | Unlocking an account is not a fresh sign in |
| [0019](0019-mac-design-system.md) | The Mac wears the design system over native controls |
| [0020](0020-mac-inspector-menu-and-back.md) | The inspector menu shows shortcuts it does not own; Back closes the inspector first |
| [0021](0021-mac-space-peek-card.md) | Space opens an in app peek card instead of the system Quick Look panel |
| [0022](0022-mac-archive-peek-card.md) | Archives open in a peek card read through the server's archive routes |
| [0023](0023-session-preferences-reset-after-sign-out.md) | Session preferences reset after the sign out screen change |
| [0024](0024-browse-cancel-ids-per-folder.md) | Browse cancel ids are keyed by the screen's folder |
