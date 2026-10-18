#!/bin/bash
set -euo pipefail

# Set the global git identity from the untracked .env, so personal details stay
# out of the repo. Honors DRY_RUN and LINUX_UTILS_ENV.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

env_file="${LINUX_UTILS_ENV:-$REPO_ROOT/.env}"

if [[ ! -f "$env_file" ]]; then
    print_warning "no git identity: copy .env.example to $env_file"
    exit 0
fi
# shellcheck source=../../.env.example
source "$env_file"

set_global() {
    local key="$1" value="$2"

    if [[ "$(git config --global --get "$key" || true)" == "$value" ]]; then
        print_success "git $key already $value"
    elif [[ "$DRY_RUN" == true ]]; then
        print_warning "would set git $key = $value"
    else
        git config --global "$key" "$value"
        print_success "set git $key = $value"
    fi
}

set_global user.name "$GIT_USER_NAME"
set_global user.email "$GIT_USER_EMAIL"
