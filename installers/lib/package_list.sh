#!/bin/bash

# Parse package-list lines for apt (and reusable tests).
# PPA lines use "package | ppa:repo".
# Sets globals: package and ppa. Returns 1 for blank/comment lines.
#
# shellcheck disable=SC2034  # ppa/package are set for callers

parse_package_line() {
    local line="$1"
    package=""
    ppa=""

    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && return 1

    if [[ "$line" =~ ^([^|#]+)\|[[:space:]]*ppa:([^#]+) ]]; then
        package=$(echo "${BASH_REMATCH[1]}" | xargs)
        ppa=$(echo "${BASH_REMATCH[2]}" | xargs)
    else
        package=$(echo "$line" | awk '{print $1}')
    fi

    [[ -n "$package" ]]
}
