# 0016. Code carries no comments; a ratchet holds the rest

Status: Accepted

## Context
Comments drifted from the code they described, repeated what the code said, or excused a
shortcut that then spread. About 10,800 comment lines sat in the Swift sources.

## Decision
- New Swift code carries no comments. A non obvious decision goes in an ADR here; a shortcut is
  fixed rather than explained; anything else is said by names and types.
- `Scripts/check-comments.py` counts comment lines per file against
  `Scripts/comment-baseline.json`. A file may lose comment lines but never gain them, and a file
  missing from the baseline may have none. House rules run it on every commit and in CI.
- MARK, swiftlint and swiftformat directives are not counted. The generated `L10n.swift` is
  excluded; its generator owns it.
- The `/delete-comment` skill repeats the sweep: tautologies and stale comments are deleted,
  the code behind an excuse is fixed, decisions move here, then the baseline is lowered.

## Consequences
Existing comments stay until a sweep removes them. Lowering the baseline is always allowed;
raising it is refused.
