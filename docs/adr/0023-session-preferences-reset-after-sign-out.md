# 0023. Session preferences reset after the sign out screen change

Status: Accepted

## Context
Signing out clears the session scoped preferences (`AppStorageKeys.sessionScopedKeys`: default sort, the
display switches, date format and the like) so the next account starts from the shipped defaults. The
reducer cleared them in the same pass that swapped the destination to the login page. Removing those
keys fires every `@AppStorage` and `@Shared(.appStorage)` reader in the outgoing signed in tree while
SwiftUI is still applying the swap. On the Mac the main window then never ran `AppView` again: it kept
showing Browse, dead to clicks, until some other change (an appearance switch) redrew it. The Settings
window, which reads the same store, did switch.

## Decision
- `teardownToLogin` swaps the destination first and clears the session preferences from a main actor
  effect, so the readers fire after the signed in tree is gone.
- The order applies to every path through `teardownToLogin`: Sign Out from Settings, the account panel
  and the lock screen, and the end of the last session.

Code: `AppFeature.teardownToLogin`, `AppStorageKeys.resetSessionPreferences`.
