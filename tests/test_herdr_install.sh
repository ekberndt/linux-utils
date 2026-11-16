#!/bin/bash
set -uo pipefail

# Herdr: which targets install the app and the core, the vendor installers
# they run, and the config sync that links the agent-tree layout and its mods,
# checks them, and switches off the default `main` layout.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/darwin"

# Force the Linux installer even when the suite runs on a Mac, and the macOS
# one where asked.
cat > "$tmp/bin/uname" <<'EOF'
#!/bin/bash
[[ "${1:-}" == -s ]] && { echo Linux; exit 0; }
exec /usr/bin/uname "$@"
EOF
cat > "$tmp/darwin/uname" <<'EOF'
#!/bin/bash
[[ "${1:-}" == -s ]] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
EOF
chmod +x "$tmp/bin/uname" "$tmp/darwin/uname"

linux() { PATH="$tmp/bin:$PATH" bash "$ROOT/installers/installer.sh" "$@"; }
macos() { PATH="$tmp/darwin:$PATH" bash "$ROOT/installers/installer.sh" "$@"; }

for profile in workstation datacenter; do
    plan="$(linux plan "$profile")"
    assert_contains "$profile installs herdr-core for the app to reach" "$plan" "herdr-core (hc)"
    assert_not_contains "$profile leaves the desktop app opt-in" "$plan" "Herdr app"
done
assert_contains "the app joins a Linux run on request" "$(linux plan herdr)" "Herdr app"
assert_contains "macOS offers the app" "$(macos list)" "Herdr app"
assert_contains "macOS offers the core" "$(macos plan herdr-core)" "herdr-core (hc)"

# The vendor installers drop their binary into ~/.local/bin; the core's brings
# hc, whose `update` moves the core to HC_UPDATE_TO when that is set.
cat > "$tmp/bin/curl" <<'CURL'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
cat <<INSTALL
mkdir -p "\$HOME/.local/bin"
printf '#!/bin/bash\necho "$FAKE_BINARY 0.1.15"\n' > "\$HOME/.local/bin/$FAKE_BINARY"
cat > "\$HOME/.local/bin/hc" <<'HC'
#!/bin/bash
printf '%s\n' "\$*" >> "\$HC_LOG"
[[ -n "\${HC_UPDATE_TO:-}" ]] && printf '#!/bin/bash\necho "hc %s"\n' "\$HC_UPDATE_TO" > "\$HOME/.local/bin/herdr-core"
exit 0
HC
chmod +x "\$HOME/.local/bin/$FAKE_BINARY" "\$HOME/.local/bin/hc"
INSTALL
CURL
chmod +x "$tmp/bin/curl"

run_component() {
    local component="$1" binary="$2"
    shift 2
    mkdir -p "$tmp/$component"
    env -i \
        HOME="$tmp/$component" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        CURL_LOG="$tmp/$component.log" \
        HC_LOG="$tmp/$component.hc.log" \
        FAKE_BINARY="$binary" \
        "$@" \
        bash "$ROOT/installers/$component/install.sh"
}

check_install() {
    local component="$1" binary="$2" url="$3" output
    output="$(run_component "$component" "$binary")"
    assert_eq "$component runs Herdr's installer" "$(< "$tmp/$component.log")" "-fsSL $url"
    assert_contains "$component reports what it installed" "$output" \
        "Successfully installed: $binary (0.1.15)"
}
check_install herdr herdr-app https://releases.herdr.dev/app/install.sh
check_install herdr-core herdr-core https://releases.herdr.dev/core/install.sh
fetches() { wc -l < "$tmp/$1.log" | tr -d ' '; }

# The app updates itself, and the core through hc; neither is fetched again.
assert_contains "an installed app is left to update itself" \
    "$(run_component herdr herdr-app)" "Already installed: herdr-app"
assert_eq "the app is not fetched again" "$(fetches herdr)" "1"

current="$(run_component herdr-core herdr-core)"
assert_eq "an installed core runs hc update" "$(< "$tmp/herdr-core.hc.log")" "update"
assert_not_contains "a current core reports no update" "$current" "Updated"
assert_contains "a newer core reports the move" \
    "$(run_component herdr-core herdr-core HC_UPDATE_TO=0.1.16)" "Updated: herdr-core 0.1.15 -> 0.1.16"
assert_eq "the core is not fetched again" "$(fetches herdr-core)" "1"

# Config sync links every mod and layout, prunes dropped repo links, checks
# mods when herdr-app is installed, and activates the agent-tree layout.
sync() { env -i HOME="$tmp/home" PATH=/usr/bin:/bin "$@" bash "$ROOT/installers/config/herdr.sh"; }
app="$tmp/home/.config/herdr-app"

sync DRY_RUN=true >/dev/null
assert_eq "a dry run links nothing" "$(test -e "$app" && echo exists || echo missing)" "missing"

sync >/dev/null
for mod in agent-tree session-menu tab-bar pane-header sidebar-footer status-bar; do
    assert_eq "mod $mod is linked from the repo" "$(readlink "$app/mods/$mod")" "$ROOT/herdr/mods/$mod"
done
assert_eq "the agent-tree layout is linked from the repo" "$(readlink "$app/layouts/agent-tree.json")" \
    "$ROOT/herdr/layouts/agent-tree.json"
assert_eq "the layout preview is linked from the repo" "$(readlink "$app/layouts/agent-tree.svg")" \
    "$ROOT/herdr/layouts/agent-tree.svg"
assert_eq "shared.json selects agent-tree on a fresh home" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["layout"])' "$app/shared.json")" "agent-tree"

rerun="$(sync)"
assert_contains "a re-run finds the layout link in place" "$rerun" "already linked: $app/layouts/agent-tree.json"
assert_contains "a re-run leaves the active layout current" "$rerun" "Herdr layout already set: agent-tree"

# Dangling links to renamed repo mods or layouts are removed, and an active
# layout pointing at a removed file switches to agent-tree while keeping other state.
ln -s "$ROOT/herdr/mods/retired-mod" "$app/mods/retired-mod"
ln -s "$ROOT/herdr/layouts/retired.json" "$app/layouts/retired.json"
printf '{"layout":"retired","agents.sort":"grouped"}' > "$app/shared.json"
sync >/dev/null
assert_eq "retired mod link is pruned" "$(test -L "$app/mods/retired-mod" && echo kept || echo gone)" "gone"
assert_eq "retired layout link is pruned" "$(test -L "$app/layouts/retired.json" && echo kept || echo gone)" "gone"
assert_eq "removed layout switches to agent-tree and keeps shared keys" \
    "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["layout"], d["agents.sort"])' "$app/shared.json")" \
    "agent-tree grouped"

# A deliberate layout pick (`win98`) is preserved across config sync.
printf '{"layout":"win98"}' > "$app/shared.json"
assert_contains "an explicit layout choice is respected" "$(sync)" "keeping Herdr layout: win98"
assert_eq "shared.json keeps win98" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["layout"])' "$app/shared.json")" "win98"

# When Herdr is running on `main`, sync checks every mod and switches live.
mkdir -p "$tmp/home/.local/bin"
cat > "$tmp/home/.local/bin/herdr-app" <<'APP'
#!/bin/bash
printf '%s\n' "$*" >> "$HERDR_APP_LOG"
case "$1" in
    check) exit 0 ;;
    status) printf '{"layout":"main"}\n' ;;
    do) exit 0 ;;
esac
APP
chmod +x "$tmp/home/.local/bin/herdr-app"
live_out="$(sync HERDR_APP_LOG="$tmp/herdr-app.log")"
assert_contains "running window checks mods" "$(< "$tmp/herdr-app.log")" "check $app/mods/agent-tree"
assert_contains "running window on main switches live to agent-tree" "$(< "$tmp/herdr-app.log")" \
    'do layout.switch {"name":"agent-tree"}'
assert_contains "live switch reports update" "$live_out" "Updated: Herdr layout -> agent-tree"

sync XDG_CONFIG_HOME="$tmp/xdg" HERDR_APP_LOG="$tmp/xdg-app.log" >/dev/null
assert_eq "XDG_CONFIG_HOME moves the app's home, as it does for the app" \
    "$(readlink "$tmp/xdg/herdr-app/mods/agent-tree")" "$ROOT/herdr/mods/agent-tree"

# The app runs on the Mac, where its home is ~/.config/herdr-app too, and the
# macOS config sync reaches the Herdr step.
mkdir -p "$tmp/mac"
mac_sync="$(env -i HOME="$tmp/mac" PATH="$tmp/darwin:/usr/bin:/bin" \
    bash "$ROOT/installers/config/install.sh" --dry-run 2>&1)"
assert_contains "macOS config sync runs the Herdr step" "$mac_sync" "Syncing herdr config"
assert_contains "macOS links agent-tree into the app's home" "$mac_sync" \
    "would link: $tmp/mac/.config/herdr-app/mods/agent-tree"
assert_contains "macOS links the agent-tree layout into the app's home" "$mac_sync" \
    "would link: $tmp/mac/.config/herdr-app/layouts/agent-tree.json"

test_result
