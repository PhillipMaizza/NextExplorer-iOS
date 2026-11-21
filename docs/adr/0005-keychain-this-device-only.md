# 0005. Secrets never leave the device

Status: Accepted

## Context
A session cookie restored onto another device is a live, signed in session with no sign in.

## Decision
- Every keychain item uses a `ThisDeviceOnly` accessibility, so it never syncs to iCloud
  Keychain or restores from a backup onto another device. This covers session credentials and
  imported client certificates (PKCS#12 bytes and passphrase).
- The Mac uses the data protection keychain like iOS, so `ThisDeviceOnly` holds and the system
  never prompts for keychain access. Releases up to 1.1.0 wrote the legacy file keychain: an item
  there moves across on first read, and every save or delete also clears the legacy copy. Builds
  without the keychain entitlement (unsigned local and CI builds) keep using the legacy keychain.
- A decoded client identity stays in memory after first use, so a TLS challenge never repeats
  key derivation. Every URL session shares the one `ClientIdentityStore`.

Code: `KeychainConfiguration`, `MacKeychainStore`, `ClientIdentityStore`.
