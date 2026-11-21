# 0006. One active cookie, many stored accounts

Status: Accepted

## Context
`HTTPCookieStorage` is what URL sessions attach to requests, but two accounts on one server share
a cookie name, domain and path and cannot coexist there.

## Decision
- The Keychain holds every signed in account's credentials (`StoredSessions`), one marked active.
- Only the active account's cookie is installed in `HTTPCookieStorage`. Switching reinstalls the
  target's cookie and never re authenticates.
- `HTTPCookieStorage.cookieAcceptPolicy` is set to `.always` before installing: it is a separate
  gate from the session configuration's policy and silently drops `setCookie` at a restrictive
  default (seen in headless test processes).
- A keychain that cannot be read throws on change paths, so a removal never saves over accounts
  it could not see.

## Consequences
A cookie the server sets later can persist on disk; tracked as issue #215.

Code: `SessionCookieStore`, `StoredSessions`.
