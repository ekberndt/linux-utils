#!/bin/bash
set -uo pipefail

# Drive upkeep the way a shell finds it: by name, through the ~/.local/bin link
# config sync makes, from directories that have nothing to do with the checkout
# it updates. That checkout is a throwaway clone carrying the real upkeep,
# .bash_aliases, and config sync beside an installer stub that logs its targets.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf -- "$tmp"' EXIT

git_q() { git -c user.email=t@t -c user.name=t "$@"; }

seed="$tmp/seed"
mkdir -p "$seed/scripts" "$seed/installers"
cp "$ROOT/scripts/upkeep" "$seed/scripts/"
cp "$ROOT/.bash_aliases" "$seed/"
cp -R "$ROOT/installers/lib" "$ROOT/installers/config" "$seed/installers/"
cat > "$seed/installers/installer.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$tmp/installed"
exit "\${STUB_INSTALLER_STATUS:-0}"
EOF
: > "$tmp/installed"

git init -q --bare -b main "$tmp/origin.git"
git_q -C "$seed" init -q -b main
git_q -C "$seed" add -A
git_q -C "$seed" commit -q -m init
git_q -C "$seed" remote add origin "$tmp/origin.git"
git_q -C "$seed" push -q origin main
checkout="$tmp/checkout"
git clone -q "$tmp/origin.git" "$checkout"

home="$tmp/home"
mkdir -p "$home" "$tmp/elsewhere" "$tmp/run"
# sync_shell <login-shell> [VAR=value]...: config sync's shell step for a user
# whose login shell is <login-shell>.
sync_shell() {
    local shell="$1"
    shift
    env -i HOME="$home" PATH="$PATH" SHELL="$shell" "$@" \
        bash "$checkout/installers/config/bash.sh" >/dev/null
}
zshrc_exists() { [[ -e "$home/.zshrc" ]] && echo exists; }

sync_shell /bin/bash
assert_eq "config sync links upkeep into ~/.local/bin" \
    "$(readlink "$home/.local/bin/upkeep")" "$checkout/scripts/upkeep"
assert_eq "a bash user gets no ~/.zshrc" "$(zshrc_exists)" ""

# A shell whose login PATH lacks ~/.local/bin, as under a systemd-started tmux
# or root. A live socket keeps .bash_aliases from starting a real ssh-agent, and
# the last line skips whatever /etc/bash.bashrc prints first.
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$tmp/run/agent"
found="$(
    env -i HOME="$home" PATH=/usr/bin:/bin TERM=dumb \
        XDG_RUNTIME_DIR="$tmp/run" SSH_AUTH_SOCK="$tmp/run/agent" \
        bash -i -c 'command -v upkeep' 2>/dev/null | tail -n 1
)"
assert_eq "an interactive shell finds upkeep on PATH" "$found" "$home/.local/bin/upkeep"

sync_shell /bin/zsh DRY_RUN=true
assert_eq "a dry run leaves ~/.zshrc alone" "$(zshrc_exists)" ""
sync_shell /bin/zsh
sync_shell /bin/zsh
assert_eq "a zsh user gets the PATH line in ~/.zshrc once" \
    "$(grep -c 'export PATH' "$home/.zshrc")" "1"
if command -v zsh >/dev/null 2>&1; then
    found="$(
        env -i HOME="$home" PATH=/usr/bin:/bin TERM=dumb \
            zsh -i -c 'command -v upkeep' 2>/dev/null | tail -n 1
    )"
    assert_eq "an interactive zsh finds upkeep on PATH" "$found" "$home/.local/bin/upkeep"
else
    echo "skip interactive zsh: zsh not installed"
fi

# run_from <dir> [VAR=value]... <command> [arg]...: run in <dir> as a fresh shell
# with the scratch HOME would, its ~/.local/bin first on PATH.
run_from() {
    local dir="$1"
    shift
    (cd "$dir" && env -i HOME="$home" PATH="$home/.local/bin:$PATH" "$@") 2>&1
}

# land <file> <line>: append <line> to <file>, then push every seed edit to
# origin/main, as a merged PR would.
land() {
    echo "$2" >> "$seed/$1"
    git_q -C "$seed" add -A
    git_q -C "$seed" commit -q -m "$2"
    git_q -C "$seed" push -q origin main
}

head_of() { git -C "$1" rev-parse "${2:-HEAD}"; }
installs() { wc -l < "$tmp/installed" | tr -d ' '; }
failed() { [[ "$1" != 0 ]] && echo failed; }

# Rewrite upkeep above the line bash is executing when the merge lands, and
# change ~/.bash_aliases under the shell that called it.
upkeep_v2="$(head -n 1 "$seed/scripts/upkeep"; printf '# %0200d\n' 0; tail -n +2 "$seed/scripts/upkeep")"
printf '%s\n' "$upkeep_v2" > "$seed/scripts/upkeep"
land .bash_aliases "# aliases v2"

out="$(run_from "$tmp/elsewhere" upkeep)"
assert_eq "upkeep by name from an unrelated directory succeeds" "$?" "0"
assert_eq "it fast-forwards its own checkout to origin/main" \
    "$(head_of "$checkout")" "$(head_of "$tmp/origin.git" main)"
assert_eq "it updates itself mid-run and installs exactly once" "$(installs)" "1"
assert_eq "it installs the workstation profile by default" "$(tail -n 1 "$tmp/installed")" "workstation"
assert_contains "it says when ~/.bash_aliases needs reloading" "$out" ".bash_aliases changed"

git_q init -q -b feat/other "$tmp/other"
git_q -C "$tmp/other" commit -q --allow-empty -m other
out="$(run_from "$tmp/other" "$home/.local/bin/upkeep" config)"
assert_eq "upkeep through its symlink from another repo succeeds" "$?" "0"
assert_contains "it updates its own checkout, not the caller's" "$out" "updating $checkout"
assert_eq "it passes targets to the installer" "$(tail -n 1 "$tmp/installed")" "config"
assert_eq "it leaves the calling repo alone" "$(git -C "$tmp/other" branch --show-current)" "feat/other"
assert_not_contains "it is quiet when ~/.bash_aliases did not change" "$out" ".bash_aliases changed"

land notes "pending"
before="$(head_of "$checkout")"
run_from "$tmp/elsewhere" upkeep plan datacenter >/dev/null
assert_eq "plan reaches the installer" "$(tail -n 1 "$tmp/installed")" "plan datacenter"
run_from "$tmp/elsewhere" upkeep list >/dev/null
assert_eq "list reaches the installer" "$(tail -n 1 "$tmp/installed")" "list"
assert_eq "plan and list leave the checkout where it was" "$(head_of "$checkout")" "$before"

count="$(installs)"
assert_contains "--help prints usage" "$(run_from "$tmp/elsewhere" upkeep --help)" "Usage:"
assert_eq "--help neither updates nor installs" "$(installs) $(head_of "$checkout")" "$count $before"

# Offline: another checkout fetched "pending" before the network went away.
real_git="$(command -v git)"
mkdir -p "$tmp/offline"
cat > "$tmp/offline/git" <<EOF
#!/bin/bash
if [[ "\$1" == fetch ]]; then
    echo "fatal: unable to access 'origin': Could not resolve host" >&2
    exit 128
fi
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/offline/git"
git -C "$checkout" fetch -q origin
fetched="$(head_of "$checkout" origin/main)"
land notes "after the network went away"

out="$(run_from "$tmp/elsewhere" PATH="$tmp/offline:$home/.local/bin:$PATH" upkeep)"
assert_eq "offline upkeep still installs" "$?" "0"
assert_contains "offline upkeep says origin was unreachable" "$out" "cannot reach origin"
assert_eq "offline upkeep fast-forwards to the last fetched origin/main" \
    "$(head_of "$checkout")" "$fetched"

# Each refusal below must install nothing and leave HEAD where it was.
count="$(installs)"
before="$(head_of "$checkout")"

echo "local edit" >> "$checkout/notes"
run_from "$tmp/elsewhere" upkeep >/dev/null
assert_eq "an edit the fast-forward would overwrite stops upkeep" "$(failed $?)" "failed"
assert_eq "the stopped run keeps the edit" "$(tail -n 1 "$checkout/notes")" "local edit"
git -C "$checkout" checkout -q -- notes

git -C "$checkout" switch -q -c feat/local
out="$(run_from "$tmp/elsewhere" upkeep)"
assert_eq "a checkout off main stops upkeep" "$(failed $?)" "failed"
assert_contains "it names the branch" "$out" "on feat/local, not main"
assert_eq "it does not switch branches" "$(git -C "$checkout" branch --show-current)" "feat/local"
git -C "$checkout" switch -q --detach main
assert_contains "a detached HEAD stops upkeep" "$(run_from "$tmp/elsewhere" upkeep)" "on a detached HEAD"
git -C "$checkout" switch -q main
assert_eq "refusals leave HEAD where it was" "$(head_of "$checkout")" "$before"

git_q -C "$checkout" commit -q --allow-empty -m "local only"
local_only="$(head_of "$checkout")"
run_from "$tmp/elsewhere" upkeep >/dev/null
assert_eq "local commits origin/main lacks stop upkeep" "$(failed $?)" "failed"
assert_eq "it keeps the local commit" "$(head_of "$checkout")" "$local_only"
assert_eq "refusals install nothing" "$(installs)" "$count"

git -C "$checkout" reset -q --hard origin/main
run_from "$tmp/elsewhere" STUB_INSTALLER_STATUS=3 upkeep >/dev/null
assert_eq "upkeep exits with the installer's status" "$?" "3"

test_result
