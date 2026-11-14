#!/bin/bash
set -uo pipefail

# herdr-core and its CLI, hc: it runs the terminals and agents the Herdr app
# shows, and is all a machine needs for the app to reach it over SSH. An
# installed core updates with `hc update`, which keeps running terminals.
# https://github.com/herdrdev/herdr-core#install

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

install_or_update herdr-core "$HOME/.local/bin" https://releases.herdr.dev/core/install.sh sh hc update
