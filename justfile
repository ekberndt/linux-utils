installer := "installers/installer.sh"

default:
    @just --list

# Install packages/tools. Defaults to installing everything; pass installer flags to scope
install *flags="--all":
    bash {{installer}} {{flags}}

# Sync tracked configs (Claude, Codex, shared scripts/skills, Neovim, tmux) via symlinks.
config:
    bash {{installer}} --config

# Run all pre-commit hooks
lint:
    pre-commit run --all-files
