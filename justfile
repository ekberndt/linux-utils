installer := "installers/installer.sh"

default:
    @just --list

# Install packages/tools. Defaults to installing everything; pass installer flags to scope
# Examples: just install --apt --cargo
#           just install --all --optionals
install *flags="--all":
    bash {{installer}} {{flags}}

# Sync tracked configs (Claude, Codex, shared scripts/skills, Neovim, tmux) via symlinks.
config:
    bash {{installer}} --config

# Unit tests for package-list parsing and installer stream filters
test:
    bash tests/run.sh

# Run all pre-commit hooks and unit tests
lint:
    pre-commit run --all-files
    bash tests/run.sh

# Chassis RGB (OpenRGB + liquidctl). See scripts/rgb --help
# OpenRGB binary: just install --openrgb  (installers/openrgb)
rgb *args:
    bash scripts/rgb {{args}}

rgb-off:
    bash scripts/rgb off

rgb-status:
    bash scripts/rgb status

# udev + /usr/local/bin/rgb + boot-off (requires OpenRGB already installed)
rgb-install:
    bash scripts/rgb install
