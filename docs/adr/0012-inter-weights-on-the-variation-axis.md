# 0012. Inter weights are set on the variation axis

Status: Accepted

## Context
Inter ships as one variable font registered at its Regular instance. UIKit has no weight modifier
for a custom font.

## Decision
Each weight is dialled in directly on the `wght` variation axis when the font is built.

Code: `FontRegistration`.
