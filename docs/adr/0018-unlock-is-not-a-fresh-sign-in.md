# 0018. Unlocking an account is not a fresh sign in

Status: Accepted

## Context
Require Sign In locks an account when the app starts or after time away: the stored cookie is
dropped from the Keychain and the jar, and the server session is ended. Unlocking asks for a
full sign in again (SSO in a private browser session, or the password form). A normal fresh sign
in wipes every cache store, so nothing of a previous account leaks into the next one.

## Decision
- A sign in at the lock screen that lands on the locked account opens it without the fresh sign
  in wipe. Its offline files, cached folders and preferences stay; they belong to that account.
- A sign in that lands on any other account is refused: that new session is removed (unless it
  was already a stored account), the locked account is made active again, and the lock screen
  says so. The other account's data is never mixed with the locked one's.
- An account set to not keep offline files has its caches and offline files wiped when it locks,
  so there is nothing to keep at unlock.
- Every logout, session expiry and sign in from the login form still clears every store.

Code: `AppFeature+Lock` (`lockSignedIn`, `unlock`, `refuseOtherAccount`, `endLockedSessions`),
`LockFeature`, `AccountCacheWipe.wipeLocked`.
