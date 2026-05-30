# linux-utils task runner.
# Install `just` (https://github.com/casey/just), then run `just` to list recipes.

# Master installer entrypoint. just runs recipes from this file's directory,
# so the relative path resolves no matter where `just` is invoked from.
installer := "installers/installer.sh"

# List available recipes (default when running a bare `just`).
default:
    @just --list

# Install packages/tools. Defaults to everything; pass installer flags to scope,
# e.g. `just install -a -f`, `just install --uv`, or `just install --help`.
install *flags="--all":
    bash {{installer}} {{flags}}

# Sync tracked config (Claude, Codex, shared scripts/skills, Neovim, tmux) via symlinks.
config:
    bash {{installer}} --config

# Run all pre-commit hooks (shellcheck, markdownlint, whitespace) over the repo.
lint:
    pre-commit run --all-files
