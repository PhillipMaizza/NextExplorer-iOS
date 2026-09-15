# Contributing to NextExplorer for iOS

Thanks for taking a look. This guide covers how the project is built and the conventions to follow when proposing a change.

## Getting set up

1. Install Xcode 16 or later.
2. Fork and clone the repo, then open `NextExplorer.xcodeproj`.
3. Swift Package Manager resolves dependencies on first build. No extra tooling to install.
4. Build and run on an iOS 18+ simulator or device.

To exercise the app end to end you need a compatible self-hosted server and an account on it. The backend contract is the source of truth: never invent an API shape, always mirror what the server actually returns.

## How to propose a change

1. Open an issue first for anything non-trivial, so the direction can be agreed before code is written.
2. Branch from `main`. Branches are named `feature/NXTIOS-XXXX-short-slug`, where `XXXX` is the next incremental ticket number, zero-padded to four digits (for example `feature/NXTIOS-0041-grid-spacing`). Do not use bare descriptive branch names.
3. Make your change, keep it on the one working branch, and open a pull request against `main` when it is ready.
4. Fill in the PR description with what changed and why, and reference the issue.

## Conventions

These keep the codebase consistent. A PR that follows them is far quicker to review.

### Architecture

- Native iOS 18+, SwiftUI, and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (`@Reducer`, `@ObservableState`, `TestStore`).
- Model each screen or data load as a single lifecycle phase (`idle` / `loading` / `loaded` / `failed`), not a cluster of `isLoading` + `hasLoaded` + `errorMessage` booleans. Derive the rest from the phase. A single in-flight flag for a mutation (like `isSaving`) is fine.
- Keep heavy work off the main actor. Image decoding, large file and JSON reads, parsing, and archive or PDF work run via `Task.detached`, never inside a `body`, a `@MainActor .task`, or a `Reduce` closure. Stream large downloads; never accumulate a response byte by byte.
- A cancelled load (tab switch, scroll away) is not a failure. Guard `!Task.isCancelled` before committing any error or fallback state.

### Views

- Break up large views. A view file past roughly 400 lines is a monolith: extract rows, menus, sheets and section groups into their own standalone `struct`s. Pass the store plus minimal inputs, not cross-file extensions.
- Each extracted view carries its own `#Preview`s covering every state: loading, loaded, empty, error, no-results.

### Localization

- Every user-facing string goes through `L10n.<key>`. No hard-coded display text.
- The app ships 17 languages. New keys are added to the string catalog for every language.

### Offline cache

- The cache is stale-while-revalidate and fallback-only: paint the saved copy, then always refetch and overwrite. Fall back to cache only on an offline error, never on a real server error.
- **Security:** every cache store must be cleared on logout, session expiry and fresh sign-in. A saved list must never leak into the next account. Any new cache store must be wired into all clear sites.

### Style

- Minimal comments. When a comment is genuinely needed, use no hyphens or em dashes in it.
- Match the naming and idiom of the surrounding code.

## Building and testing before you push

- Build and run every change on the QA simulator: **iPhone 17 Pro, iOS 27**. Use this for builds, package tests and any visual QA pass.
- Run the test suite (`Product > Test`, or `xcodebuild test` against a matching simulator) and make sure it passes.
- Confirm the app still builds cleanly before opening the PR.

## Questions

Open an issue or reach out through the [support site](https://nextexplorer.phillipmaizza.com). Happy to help you get oriented.
