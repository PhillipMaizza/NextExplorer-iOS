# Contributing to NextExplorer for iOS

Thanks for taking a look. This guide covers how the project is built and the conventions every change follows. They are not stylistic preferences; they keep the app fast, private and account-safe, and a PR that follows them is far quicker to review.

## Getting set up

1. Install Xcode 16 or later.
2. Fork and clone the repo, then open `NextExplorer.xcodeproj`.
3. Swift Package Manager resolves dependencies on first build. No extra tooling.
4. Build and run on an iOS 18+ simulator or device. To exercise the app end to end you need a compatible self-hosted server and an account on it.

## Source of truth

The backend contract is authoritative. Never invent an API shape, a limit or a validation rule: mirror what the server actually returns and enforces. Validators on device exist to match the backend, not to guess at one.

## Proposing a change

1. Open an issue first for anything non-trivial, so the direction is agreed before code is written.
2. Branch from `main`. Branches are named `feature/NXTIOS-short-slug` (for example `feature/NXTIOS-grid-spacing`). No bare descriptive branch names.
3. Keep the change on the one working branch and open a pull request against `main` when it is ready. Describe what changed and why, and reference the issue.

## Architecture

- Native iOS 18+, SwiftUI, and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (`@Reducer`, `@ObservableState`, `TestStore`).
- Follow the existing architecture and preserve dependency direction. Reuse existing infrastructure and TCA dependencies rather than adding parallel ones. No unrelated refactors in a feature PR.

### State modelling

- Model each screen or data load as a single lifecycle phase: `DataPhase` (`idle` / `loading` / `loaded` / `failed`). Derive `hasLoaded`, `errorMessage` and `shouldLoadOnAppear` from the phase. Do not spread one lifecycle across `isLoading` + `hasLoaded` + `errorMessage` booleans. A single in-flight flag for a mutation (like `isSaving`) is fine; two or more booleans encoding one lifecycle is not.
- Model errors by meaning (validation, auth, expired session, rate limit, network, server, decoding). Never surface a raw technical error to the user.

### Concurrency

- Keep heavy work off the main actor. Image decode and downsample, large file and JSON reads, Markdown / tree-sitter / regex parsing, and PDF or archive work run via `Task.detached`, never inside a `body`, a `@MainActor .task`, or a `Reduce` closure.
- Stream large transfers. Use `URLSession.download`; never accumulate a response byte by byte with `URLSession.bytes`.
- Cancellation is not failure. In a view `.task`, guard `!Task.isCancelled` before committing any error, fallback or failed state. A cancelled load (tab switch, scroll away) must not flash an error.
- Split cancel IDs so unrelated effects do not cancel each other.

### Offline cache

- Stale-while-revalidate and fallback-only: paint the saved copy, then always refetch and overwrite. Fall back to cache only on an offline error, never on a real server error.
- **Security, non-negotiable:** every cache store is cleared on logout, session expiry and fresh sign-in. A saved list must never leak into the next account. Any new cache store must be wired into all clear sites.

## UI and design system

- Use DesignSystem components and tokens. Prefer a token over a local constant.
- **No magic numbers.** File or view specific constants belong in a `private enum Constants`. Share small constants across split files with a `private typealias Metrics = ...` alias or a per-file `private enum Constants` subset; do not duplicate a full metrics enum.
- Break up large views. A view file past roughly 400 lines is a monolith: extract rows, menus, sheets and section groups into their own standalone `struct`s, passing the store plus minimal inputs (not cross-file extensions, since Swift `private` is file-scoped).
- Each extracted view carries its own `#Preview`s covering every state: loading, loaded, empty, error, no-results.

## Localization

- Every user-facing string goes through `L10n.<key>`. No hard-coded display text.
- The app ships 17 languages. A new key is added to the string catalog for every language, with placeholder validation intact.
- Do not hand-edit the generated catalog. Edit the source and regenerate with the scripts below.

## Scripts

Two helpers under `Scripts/` drive localization. The `Localization` package is generated, so localization changes flow through these, not by editing `Localizable.xcstrings` or `L10n.swift` directly.

- **`gen-l10n.py`** regenerates the `Localization` package from its human-edited source. `Packages/Localization/strings.tsv` (one `key<TAB>English` per line) is the source of truth; the script rewrites `Localizable.xcstrings` and the two-level `L10n.swift` accessors, folds in each `translations/<lang>.tsv`, falls back to English for missing keys, and re-checks placeholder integrity. Run it after any string change: `python3 Scripts/gen-l10n.py`.
- **`machine-translate.py`** fills `translations/<lang>.tsv` for the non-hand-authored languages via deep-translator's keyless MyMemory backend. Format specifiers (`%@`, `%lld`, `%1$@`, ...) are masked before translation and restored after, so none are dropped; per-string failures fall back to English. Its output is always re-validated by `gen-l10n.py`.

## Naming and style

- Boolean properties begin with `is`, `are`, `has`, `can` or `should`.
- Match the naming and idiom of the surrounding code.
- Comments are minimal, and carry no hyphens or em dashes.

## Build and test before you push

- Build and run every change on the QA simulator: **iPhone 17 Pro, iOS 27**. Use it for builds, package tests and any visual QA pass.
- Run the relevant unit and package tests (`Product > Test`, or `xcodebuild test` against a matching simulator) and make sure they pass.
- Confirm strings are localized, there are no magic numbers, and the app builds cleanly before opening the PR.

## Questions

Open an issue or reach out through the [support site](https://phillipmaizza.com/nextexplorer). Happy to help you get oriented.
