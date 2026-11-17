#!/bin/sh
# Points git at the repository's hooks: the house rule checks run on every commit.
set -e
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "Hooks installed from .githooks"
