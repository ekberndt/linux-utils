#!/bin/bash
set -euo pipefail

# Link every Herdr mod and layout in herdr/ into the app's home, check each
# mod when herdr-app is installed, and activate the agent-tree layout when
# Herdr is still on its shipped `main` layout (or a layout whose file is gone).
# Honors DRY_RUN.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# The app's own lookup order.
APP_HOME="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
LAYOUT_NAME="agent-tree"

for mod_manifest in "$REPO_ROOT"/herdr/mods/*/mod.json; do
    mod_dir="$(dirname "$mod_manifest")"
    apply_link "$mod_dir" "$APP_HOME/mods/$(basename "$mod_dir")"
done

if [[ -d "$APP_HOME/mods" ]]; then
    for link in "$APP_HOME/mods"/*; do
        [[ -L "$link" && ! -e "$link/mod.json" && "$(readlink "$link")" == "$REPO_ROOT/herdr/mods/"* ]] || continue
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "would remove: $link"
        else
            rm -- "$link"
            print_updated "$link (removed)"
        fi
    done
fi

for layout_file in "$REPO_ROOT"/herdr/layouts/*; do
    apply_link "$layout_file" "$APP_HOME/layouts/$(basename "$layout_file")"
done

if [[ -d "$APP_HOME/layouts" ]]; then
    for link in "$APP_HOME/layouts"/*; do
        [[ -L "$link" && ! -e "$link" && "$(readlink "$link")" == "$REPO_ROOT/herdr/layouts/"* ]] || continue
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "would remove: $link"
        else
            rm -- "$link"
            print_updated "$link (removed)"
        fi
    done
fi

herdr_app=""
if command -v herdr-app >/dev/null 2>&1; then
    herdr_app="herdr-app"
elif [[ -x "$HOME/.local/bin/herdr-app" ]]; then
    herdr_app="$HOME/.local/bin/herdr-app"
fi

if [[ -n "$herdr_app" && "$DRY_RUN" == false ]]; then
    for mod_manifest in "$REPO_ROOT"/herdr/mods/*/mod.json; do
        mod_name="$(basename "$(dirname "$mod_manifest")")"
        HERDR_APP_HOME="$APP_HOME" "$herdr_app" check "$APP_HOME/mods/$mod_name" >/dev/null
        print_success "checked mod: $mod_name"
    done
fi

# Switch when Herdr is still on `main`, has not chosen a layout yet, or points
# at a layout whose file no longer exists; leave deliberate picks (`win98`,
# `terminals`, or another personal layout) untouched.
should_activate_layout() {
    local current="$1"
    [[ -z "$current" || "$current" == "main" ]] && return 0
    [[ "$current" == "$LAYOUT_NAME" || "$current" == "terminals" || "$current" == "win98" ]] && return 1
    [[ ! -e "$APP_HOME/layouts/$current.json" && ! -e "$REPO_ROOT/herdr/layouts/$current.json" ]]
}

if [[ -n "$herdr_app" ]] && status_json="$(HERDR_APP_HOME="$APP_HOME" "$herdr_app" status 2>/dev/null)"; then
    current="$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("layout") or "main")' <<<"$status_json")"
    if [[ "$current" == "$LAYOUT_NAME" ]]; then
        print_success "Herdr layout already active: $LAYOUT_NAME"
    elif should_activate_layout "$current"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_success "would switch Herdr layout: $current -> $LAYOUT_NAME"
        else
            HERDR_APP_HOME="$APP_HOME" "$herdr_app" "do" layout.switch "{\"name\":\"$LAYOUT_NAME\"}" >/dev/null
            print_updated "Herdr layout -> $LAYOUT_NAME"
        fi
    else
        print_success "keeping Herdr layout: $current"
    fi
else
    shared_file="$APP_HOME/shared.json"
    current=""
    if [[ -f "$shared_file" ]]; then
        current="$(python3 - "$shared_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    print(data.get("layout") or "" if isinstance(data, dict) else "")
except Exception:
    print("")
PY
)"
    fi
    if [[ "$current" == "$LAYOUT_NAME" ]]; then
        print_success "Herdr layout already set: $LAYOUT_NAME"
    elif should_activate_layout "$current"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_success "would set Herdr layout: ${current:-main} -> $LAYOUT_NAME"
        else
            mkdir -p "$APP_HOME"
            python3 - "$shared_file" "$LAYOUT_NAME" <<'PY'
import json, os, sys, tempfile

path, layout = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict) :
            data = loaded
    except Exception:
        pass
data["layout"] = layout
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".shared.")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh, separators=(",", ":"))
os.replace(tmp, path)
PY
            print_updated "Herdr layout -> $LAYOUT_NAME ($shared_file)"
        fi
    else
        print_success "keeping Herdr layout: $current"
    fi
fi
