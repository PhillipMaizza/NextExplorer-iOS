# 0014. Mac UI tests type on the ABC layout

Status: Accepted

## Context
XCUITest types with US key codes. On another layout (Italian puts `[` and `]` elsewhere) ⌘[
becomes another shortcut and typed names come out wrong.

## Decision
Each Mac UI test switches to the ABC layout and restores the person's own layout when it ends.

Code: `NextExplorerUITests/KeyboardLayout.swift`.
