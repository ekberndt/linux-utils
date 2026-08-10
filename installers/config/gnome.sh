#!/bin/bash
set -euo pipefail

# Hide Help and App Center from the GNOME dock without touching the user's
# other pinned applications. Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

hidden_favorites=(
    yelp.desktop
    org.gnome.Software.desktop
    snap-store_snap-store.desktop
    snap-store_ubuntu-software.desktop
)

if [[ "$(uname -s)" != "Linux" ]] || ! gsettings_has_schema org.gnome.shell; then
    print_warning "skipping GNOME dock preferences (GNOME Shell unavailable)"
    exit 0
fi

favorites="$(gsettings get org.gnome.shell favorite-apps)"
filtered="$(
    python3 - "$favorites" "${hidden_favorites[@]}" <<'PY'
import ast
import sys

serialized = sys.argv[1]
if serialized.startswith("@as "):
    serialized = serialized[4:]
hidden = set(sys.argv[2:])
print(repr([favorite for favorite in ast.literal_eval(serialized) if favorite not in hidden]))
PY
)"

if [[ "$favorites" == "$filtered" ]]; then
    print_success "GNOME dock already hides Help and App Center"
elif [[ "$DRY_RUN" == true ]]; then
    print_warning "would hide Help and App Center from the GNOME dock"
elif gsettings set org.gnome.shell favorite-apps "$filtered"; then
    print_success "GNOME dock hides Help and App Center"
else
    print_warning "Could not update GNOME dock favorites"
fi
