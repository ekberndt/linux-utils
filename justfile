# Absolute so recipes stay correct even if the shell cwd is not the repo root
# (just also sets working-directory to the justfile dir by default).
installer := justfile_directory() / "installers" / "installer.sh"

default:
    @just --list

# Examples: just install datacenter
#           just install workstation --optionals
#           just install workstation desktop-apps
#           just install uv cargo config
# From anywhere after config sync: linux-utils-install [targets]
# Install. macOS: Homebrew packages and agent config. Linux: named profile (default workstation).
install *targets="workstation":
    bash {{installer}} {{targets}}

# Resync tracked config without installing packages.
config:
    bash {{installer}} config

# Installer and config unit tests
test:
    bash tests/run.sh

# Run all pre-commit hooks and unit tests
lint:
    pre-commit run --all-files
    bash tests/run.sh

# Chassis RGB → scripts/rgb (OpenRGB from: just install openrgb)
# Args: status | off | on [RRGGBB] | color RRGGBB | install | install-openrgb
#       install-udev | install-system | install-boot | uninstall-boot | doctor
rgb *args:
    bash scripts/rgb {{args}}

# Flash USB Rubber Ducky with linux-utils Ubuntu bootstrap (Ducky must be mounted)
# Example: just ducky-flash
#          just ducky-flash ducky/payloads/ubuntu-install.txt
ducky-flash *payload:
    bash {{ justfile_directory() }}/ducky/flash.sh {{payload}}
