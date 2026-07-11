#!/bin/bash

# Parse package-list lines for apt (and reusable tests).
# Optional lines start with "? ". PPA lines use "package | ppa:repo".
# Sets globals: package, optional, ppa. Returns 1 for blank/comment lines.
#
# shellcheck disable=SC2034  # optional/ppa/package are set for callers

parse_package_line() {
    local line="$1"
    optional=false
    package=""
    ppa=""

    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && return 1

    if [[ "$line" =~ ^\?[[:space:]]+(.*) ]]; then
        optional=true
        line="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
        ppa=$(echo "${BASH_REMATCH[2]}" | xargs)
    else
        package=$(echo "$line" | awk '{print $1}')
    fi

    [[ -n "$package" ]]
}
