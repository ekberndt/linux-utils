#!/bin/bash
set -uo pipefail

# Run the land skill's close_terminal.sh under stub tmux and hc that log what
# they are asked to do. Each stub reports its pane or terminal as one of this
# script's ancestors, near (its parent) or far (this test), or as a process
# that is no ancestor at all, the way an inherited TMUX_PANE or HC_TERMINAL_ID
# points somewhere else.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

close="$ROOT/skills/land/scripts/close_terminal.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Resolve near/far/none to a pid when the stub is asked, after the parent that
# "near" names has written its pid.
cat > "$tmp/pid_of" <<EOF
#!/bin/bash
case "\$(cat "$tmp/\$1")" in
    near) cat "$tmp/near" ;;
    far) echo $$ ;;
    *) echo 999999 ;;
esac
EOF
cat > "$tmp/bin/tmux" <<EOF
#!/bin/bash
echo "tmux \$*" >> "$tmp/log"
[[ "\$1" == display-message ]] && bash "$tmp/pid_of" tmux_is
exit 0
EOF
# run executes the helper at once, so its kill and rm land in the log too.
cat > "$tmp/bin/hc" <<EOF
#!/bin/bash
echo "hc \$*" >> "$tmp/log"
case "\$1" in
    get) printf '{"pid": %s}\n' "\$(bash "$tmp/pid_of" herdr_is)" ;;
    run) while [[ "\$1" != -- ]]; do shift; done; shift; "\$@" ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/tmux" "$tmp/bin/hc"

# close_with <tmux: near|far|none|unset> <herdr: near|far|none|unset>
close_with() {
    local -a env=(HOME="$tmp" PATH="$tmp/bin:$PATH")
    [[ "$1" != unset ]] && env+=(TMUX_PANE=%7)
    [[ "$2" != unset ]] && env+=(HC_TERMINAL_ID=t9)
    echo "$1" > "$tmp/tmux_is"
    echo "$2" > "$tmp/herdr_is"
    : > "$tmp/log"
    # shellcheck disable=SC2016 # Expanded by the intermediate bash.
    env -i "${env[@]}" bash -c 'echo $$ > "$1"; bash "$2"' _ "$tmp/near" "$close" 2>&1
}

close_with near unset >/dev/null
assert_eq "an agent in tmux exits cleanly" "$?" "0"
assert_contains "it kills its own pane" "$(< "$tmp/log")" "tmux kill-pane -t %7"

close_with unset near >/dev/null
assert_eq "an agent in Herdr exits cleanly" "$?" "0"
herdr_log="$(< "$tmp/log")"
assert_contains "it stops Herdr putting a shell in its place" "$herdr_log" "hc keep t9 --off"
assert_contains "it starts the helper outside its own process tree" "$herdr_log" "hc run --bg --no-parent --rm"
assert_contains "the helper ends its terminal" "$herdr_log" "kill t9"
assert_contains "and then removes it" "$herdr_log" "rm t9"

close_with far near >/dev/null
assert_not_contains "a Herdr core's inherited tmux pane survives" "$(< "$tmp/log")" "kill-pane"
assert_contains "the nearer Herdr terminal closes" "$(< "$tmp/log")" "kill t9"

close_with near far >/dev/null
assert_contains "tmux run inside Herdr closes its pane" "$(< "$tmp/log")" "tmux kill-pane -t %7"
assert_not_contains "and leaves the Herdr terminal alone" "$(< "$tmp/log")" "kill t9"

out="$(close_with none unset)"
assert_eq "a pane that is not this agent's is not closed" "$?" "1"
assert_not_contains "nothing is killed" "$(< "$tmp/log")" "kill"
assert_contains "it says so" "$out" "no tmux pane or Herdr terminal"

test_result
