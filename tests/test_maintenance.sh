#!/bin/bash
set -uo pipefail

# MAINTENANCE.md points agents at files; a renamed or deleted one strands its
# item. Every backticked repo path in it must exist. A path whose top-level
# directory is not in the repo (~/.claude/..., owner/repo) is not a repo path.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$ROOT" || exit 1
# shellcheck disable=SC2016 # The backticks are Markdown code spans, not a command.
paths="$(grep -oE '`[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]*`' MAINTENANCE.md | tr -d '`' | sort -u)"
missing=""
while read -r path; do
    [[ -e "${path%%/*}" && ! -e "$path" ]] && missing+="$path "
done <<< "$paths"

assert_contains "MAINTENANCE.md names repo paths" "$paths" "installers/components.sh"
assert_eq "every repo path MAINTENANCE.md names exists" "$missing" ""

test_result
