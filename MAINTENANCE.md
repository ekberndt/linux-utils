# Maintenance

What in this repo goes stale while nobody touches it: versions pinned or
fetched at install time, files copied from upstream, config that follows
another tool's schema, code written for particular Ubuntu releases, shims meant
to be deleted, and docs that restate the code. Each item says where it lives,
how to check it, how to update it, and how to confirm the update worked.

## Running a pass

When asked to check this file:

1. Create a worktree off fresh `origin/main` with the `worktree` skill and work
   only there. Confirm the baseline passes before changing anything:
   `bash tests/run.sh` and `~/.local/bin/uvx pre-commit run --all-files`.
2. Go through the sections in order. Run each item's **Check**; if it is
   current, move on. If it is stale, apply **Update**, run **Verify**, and
   commit that item on its own. Stop and ask instead of guessing when an update
   needs a decision: dropping or adding an Ubuntu release, changing a model,
   deleting a shim, removing a package someone may still want.
3. Report to the user, per section: what was current, what you updated
   (old → new), what is stale but left alone and why, and what could not be
   checked here and where it has to run (the Mac, a GPU workstation, another
   machine). Push and open a PR only when the user asks for `land`; title it
   `chore(maintenance): <what changed>`.

Fetching:

- Agents run under `agents/permissions.json`, which denies `curl`, `wget`,
  `sudo`, and `rm`. Read web pages and APIs with WebFetch, GitHub with `gh api`
  or `git ls-remote`. Hand anything that needs `curl` or root to the user as a
  `! <command>` line.
- Put downloads and upstream clones in `mktemp -d`, never in the worktree.

No last-checked dates are kept here: a date per item would change on every
pass, so every pass would be a diff even when nothing was stale. The record is
git. Passes that changed something are the `chore(maintenance)` commits
(`git log --oneline --grep '^chore(maintenance)'`); "since the last pass" below
means since the newest of them. A pass that finds nothing stale changes
nothing and is reported to the user only.

Items marked *(in flight: `<branch>`)* describe a branch that has not merged.
When it merges, drop the mark; if it never merges, drop the item.

### Throwaway container

Installer changes that only download and install (vendor scripts, release
binaries, `cargo`, `gh`, `lazyvim` as root) can be verified as root in a
container, the same path the `datacenter` profile takes. Change the image tag
to try another Ubuntu release. Components that need a desktop, a GPU, systemd,
a non-root user, or Homebrew run on a real machine with
`bash installers/installer.sh <component>`.

```bash
docker run --rm -v "$PWD:/repo:ro" ubuntu:24.04 bash -c 'apt-get update -qq &&
  apt-get install -y -qq curl ca-certificates git >/dev/null &&
  bash /repo/installers/installer.sh <component>...'
```

## Repo tooling

### pre-commit hooks

**Where:** hook `rev`s in `.pre-commit-config.yaml` (pre-commit-hooks,
shellcheck-py, markdownlint-cli).

**Check:** `pre-commit autoupdate` rewrites the revs; a diff means stale.

```bash
~/.local/bin/uvx pre-commit autoupdate && git diff .pre-commit-config.yaml
```

**Update:** keep the diff. A new shellcheck or markdownlint can flag new
findings across the repo; fix them rather than disabling the rule.

**Verify:** `~/.local/bin/uvx pre-commit run --all-files`. It checks tracked
files only, so `git add` new files first.

### GitHub Actions

**Where:** `uses:` lines in `.github/workflows/pre-commit.yml` and
`.github/workflows/tests.yml`. Runners float on `ubuntu-latest` and Python
`3.x`; when `ubuntu-latest` moves to a new Ubuntu, CI's tmux and zsh come from
that release.

**Check:**

```bash
grep -ho 'uses: [^ ]*' .github/workflows/*.yml | sort -u
for a in actions/checkout actions/setup-python; do
  gh api "repos/$a/releases/latest" --jq "\"$a \" + .tag_name"
done
```

**Update:** bump each `@vN` to the latest major after reading its release notes
for removed inputs or runtime changes.

**Verify:** both workflows pass on the PR (`gh pr checks`).

## Docs that describe code

Cheap; check every pass, and whenever the registry, a profile, or config sync
changes.

### README profile table

**Where:** the Profiles table in `README.md` against
`installers/profiles/*.conf`, and its macOS row against `MACOS_COMPONENTS` in
`macos/install.sh`.

**Check:** left column is names only the README lists, right column names only
the profile has. Expected noise: `workstation` and `desktop-apps` (README), and
`apt`, `docker`, `homebrew`, `nvidia-driver` (described in prose).

```bash
row=$(grep '^| `workstation`' README.md)
comm -3 <(grep -o '`[a-z-]*`' <<<"$row" | tr -d '`' | sort -u) \
  <(sed -n '/PROFILE_COMPONENTS=(/,/)/p' installers/profiles/workstation.conf |
    grep -v '[()]' | tr -d ' ' | sort -u)
```

Read the `datacenter` row's prose against `installers/profiles/datacenter.conf`
and the macOS row's component list against `MACOS_COMPONENTS`.

**Update:** make the README match the profiles; the profiles are the truth.

**Verify:** `~/.local/bin/uvx pre-commit run --files README.md`.

### README tracked-config table

**Where:** the Tracked Config table in `README.md` against the `TOOLS` list in
`installers/config/install.sh` and each `installers/config/<tool>.sh` (source,
target, link or merge).

**Check:** for each `<tool>.sh`, the README row names the same sources and
targets. Preview what sync does with `bash installers/config/install.sh --dry-run`.

**Update:** fix the row. **Verify:** pre-commit on `README.md`.

### installers/installers.md

**Where:** `installers/installers.md`: profile prose, component contracts,
package manifest table, Output section, "Adding a component", helper table.

**Check:**

- Profile prose and contracts against `installers/profiles/*.conf` and each
  component's `install.sh`.
- "Adding a component" field list against the parse line in
  `installers/installer.sh` (`IFS='|' read -r name label script uses_sudo`).
- Output section against `STEPS_LOG_ROOT` and `STEPS_KEEP_RUNS` in
  `installers/lib/steps.sh`.
- Manifest table against the files and parsers in `installers/lib/packages.sh`.
- Helper table against the functions in `installers/lib/`:

```bash
sed -n '/^| Helper/,/^$/p' installers/installers.md | cut -d'|' -f2 |
  grep -o '`[a-z_]*`' | tr -d '`' | while read -r h; do
    grep -q "^$h()" installers/lib/*.sh || echo "missing helper: $h"
  done
```

**Update:** fix the doc. **Verify:** pre-commit on the file.

### Other READMEs and comments

**Where and check:**

- `macos/README.md` against `macos/install.sh`, `macos/brew.txt`, and the
  Darwin `TOOLS` in `installers/config/install.sh`.
- `ducky/README.md` and `ducky/payloads/ubuntu-install.txt` against the entry
  point they run (`scripts/resync`) and the profile names.
- `herdr/README.md` against the mod and the layout's `cloned_from.version`.
  *(in flight: `feat/herdr-installer`)*
- `justfile` recipe comments against `scripts/rgb` usage and installer targets.
- The glyph tables in `README.md` and the comment in `tmux/tmux.conf` against
  `GLYPHS` in `scripts/agent-tmux`.
- URLs in comments and docs. List them, then open each (WebFetch, or `gh api`
  for GitHub); fix moved and dead links:

```bash
git grep -ohE "https?://[^]) \"'\`>]+" | sort -u
```

**Verify:** pre-commit on the changed files; after payload edits,
`python3 tests/test_ducky_encode.py` and `bash tests/test_ducky_flash.sh`.

## Cross-file invariants

### Branch types

**Where:** `skills/worktree/SKILL.md` (branch `type`) and
`CONVENTIONAL_PREFIXES` in `scripts/agent-tmux`, which strips them from window
names.

**Check:** prints `same` when they agree.

```bash
diff <(grep -o 'type is one of `[^`]*`' skills/worktree/SKILL.md |
    sed 's/.*`\(.*\)`/\1/' | tr '|' '\n' | sort) \
  <(sed -n '/^CONVENTIONAL_PREFIXES = (/,/^)/p' scripts/agent-tmux |
    grep -o '"[a-z]*/"' | tr -d '"/' | sort) && echo same
```

**Verify:** `bash tests/test_agent_tmux.sh`.

### Cross-platform components

**Where:** a component that runs on Linux and macOS is listed in both
`COMPONENTS` (`installers/installer.sh`) and `MACOS_COMPONENTS`
(`macos/install.sh`), and in the README's macOS row.

**Check:** the names both registries list; compare with the components whose
`install.sh` has no Linux-only step.

```bash
comm -12 <(grep -o '^    "[a-z-]*|' installers/installer.sh | tr -d ' "|' | sort) \
  <(sed -n '/^MACOS_COMPONENTS=(/,/^)/p' macos/install.sh |
    grep -o '"[a-z-]*|' | tr -d '"|' | sort)
```

**Verify:** `bash tests/test_macos_install.sh`, `bash tests/test_installer_plan.sh`.

### Every install channel has an upgrade path

The installer installs only what is missing; `updateall` in `.bash_aliases`
upgrades apt, flatpak, snap, brew, pnpm, npm, pip, pipx, uv (self and tools),
rustup, and cargo (with cargo-update). Nothing upgrades the GitHub release
binaries (Neovim under `/opt`, bazelisk, buildtools), `gh` extensions, or
vendor-script installs that do not update themselves (zoxide, ollama).
*(in flight: `feat/install-upgrades-installed` moves upgrades into the
installer; rewrite this item when it merges.)*

**Check:** list the channels the installers use (`git grep -n 'install_from_web_script\|releases/latest\|apt_install\|uv tool install\|cargo install\|npm install\|gh extension install' installers/`)
and confirm each has an upgrade step. A new channel without one is the finding.

**Update:** add the upgrade step next to the others in `updateall`.

**Verify:** run `updateall` on a workstation.

## Agent CLI config

The CLIs update themselves, so check every pass. Note the versions first
(with `~/.local/bin` on `PATH`): `claude --version`, `codex --version`,
`agy --version`, `grok --version`, `opencode --version`.

### Claude Code settings

**Where:** `claude/settings.json` plus `agents/permissions.json`, merged into
`~/.claude/settings.json` by `installers/config/claude.sh`.

**Check:**

- Every key against the schema in `$schema`
  (`https://www.schemastore.org/claude-code-settings.json`; the
  `json.schemastore.org` URL redirects there). It is ~230k characters, so page
  through it with WebFetch's offset and ask, for each key the file sets,
  whether it is defined and whether it is marked deprecated.
- Hook events and `Notification` matchers against
  `https://code.claude.com/docs/en/hooks`.
- On a synced machine, `claude doctor` reports invalid settings.
- Allow rules that auto mode (`defaultMode: auto`) refuses, such as ones that
  run arbitrary code. `/auto-mode-setup` deletes them from the live file only,
  and the next sync puts them back. On a machine where it ran, list the rules
  the repo has and the live file lacks:

```bash
python3 -I - <<'EOF'
import json, pathlib
live = json.loads((pathlib.Path.home() / ".claude/settings.json").read_text())["permissions"]
repo = json.loads(pathlib.Path("agents/permissions.json").read_text())["permissions"]
for kind in ("allow", "deny"):
    print(kind, [rule for rule in repo[kind] if rule not in live.get(kind, [])])
EOF
```

**Update:** replace deprecated keys with their successors; keep the hook
wiring in step with `scripts/agent-tmux`; delete from `agents/permissions.json`
the rules auto mode refuses.

**Verify:** `python3 tests/test_inject_config.py`;
`bash installers/config/install.sh --dry-run`; then sync on a machine
(`bash installers/installer.sh config`) and start `claude`.

### Shared permissions and OpenCode

**Where:** `agents/permissions.json` is written in Claude's rule syntax
(`Bash(cmd *)`, `Read(path)`). `installers/config/opencode.sh` merges it with
`opencode/config.jsonc` into `~/.config/opencode/opencode.jsonc`, and
OpenCode's schema (`$schema`: `https://opencode.ai/config.json`) has its own
permission shape and rejects unknown top-level keys.

**Check:** WebFetch the OpenCode schema and compare every top-level key of the
merged result, and the shape of its permission rules. Check the Claude tool
names in the allow list (`Glob`, `Grep`, `WebFetch`, `WebSearch`) against
`https://code.claude.com/docs/en/settings`.

**Update:** give OpenCode rules in its own shape, or stop merging the Claude
file into it; ask the user which.

**Verify:** `python3 tests/test_inject_config.py`; on a machine with OpenCode,
sync and start `opencode`, which must load the config without errors.

### Codex

**Where:** `codex/config.toml` (merged into `~/.codex/config.toml`) and the
repo-local `.codex/config.toml`: model, reasoning keys, `approval_policy`,
`default_permissions`, `approvals_reviewer`, `service_tier`, `[features]`,
`[agents]`, `[tui]`, and hooks (SessionStart, UserPromptSubmit,
PermissionRequest, Stop, SessionEnd).

**Check:**

- `codex features list`: a feature now `stable` may not need its flag; a
  `removed` one must go.
- Every key against the config reference,
  `https://learn.chatgpt.com/docs/config-file/config-reference` (page through
  it), for deprecations and renames.
- The hook event list in the same reference. The comment in
  `codex/config.toml` says Codex has no Notification or StopFailure event;
  if one appears, wire it like Claude's.

**Update:** follow the reference.

**Verify:** `python3 tests/test_inject_config.py`; sync, start `codex`, and
watch the tmux window glyph change on a prompt.

### Grok and Antigravity

**Where:** `grok/config.toml`, `grok/hooks/agent-tmux.json` (SessionStart,
PreInvocation, PreToolUse with an `ask_question` matcher, PostToolUse, Stop;
each hook prints a JSON decision); `agy/settings.json`, `agy/hooks.json`.

**Check:** `grok doctor` on a synced machine; the hook and settings docs
(`https://docs.x.ai/build/overview`,
`https://antigravity.google/docs/getting-started`) for renamed events and keys.

**Verify:** `bash tests/test_agy.sh`, `bash tests/test_agent_tmux.sh`; start
each CLI after a sync and watch the window glyph.

### Models

**Where:** `model` in `claude/settings.json`, `codex/config.toml`, and
`agy/settings.json`.

**Check:** each still exists (the CLI refuses an unknown model at startup) and
whether the provider has a newer one.

**Update:** the user's call. Propose newer models in the report; do not switch
them unasked.

### Status line payload

**Where:** `scripts/statusline-worktree` reads the status-line JSON from
Claude Code and Antigravity (`workspace.current_dir`, `workspace.repo.name`,
`model.display_name`, `effort.level`, `fast_mode`, `session_name`,
`transcript_path`, `context_window.*`, `rate_limits.five_hour.used_percentage`)
and the transcript's `message.usage`.

**Check:** every field it reads is still listed at
`https://code.claude.com/docs/en/statusline`, and whether the payload now
carries something the script computes itself (it polls `gh pr list` for the
PR number).

**Verify:** `python3 tests/test_statusline_worktree.py`.

### Skills

**Where:** `skills/*/SKILL.md` frontmatter (`name`, `description`, and
Claude's `argument-hint`, `user-invocable`), Codex's
`skills/worktree/agents/openai.yaml`, and the directories each CLI reads:
`~/.agents/skills` (`installers/config/agents.sh`; Grok via `[skills]` in
`grok/config.toml`), `~/.claude/skills`, `~/.gemini/config/skills`.
`skills/land/scripts/next_check.py` also depends on GitHub's `gh pr view`
enums (`mergeStateStatus`, check states).

**Check:** each CLI's skills docs for frontmatter fields and discovery
directories; each CLI lists all the repo's skills. For `next_check.py`:
`gh pr view <recent PR> --json state,mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest`
still returns those fields and values in its sets.

**Verify:** `python3 tests/test_next_check.py`,
`bash tests/test_cleanup_worktrees.sh`.

### macOS app config (on the Mac)

**Where:** `macos/warp-settings.toml` (merged into `~/.warp/settings.toml`)
and `macos/.aerospace.toml`, which is AeroSpace's default config with edits.

**Check:** Warp still honors each key (after `just config`, the setting shows
in Warp; a copy from remote tmux reaches the Mac clipboard). For AeroSpace,
diff upstream's default config at the installed version (`aerospace --version`;
tags: `gh api repos/nikitabobko/AeroSpace/tags --jq '.[0].name'`):

```bash
gh api -H 'Accept: application/vnd.github.raw' \
  "repos/nikitabobko/AeroSpace/contents/docs/config-examples/default-config.toml?ref=<tag>" |
  diff - macos/.aerospace.toml
```

**Update:** take upstream's new keys and `config-version`; keep our edits.

**Verify:** `bash tests/test_aerospace_config.sh`,
`python3 tests/test_aerospace_workspaces.py`; `aerospace reload-config` on the
Mac.

## Package manifests

**Where:** `installers/apt/apt_packages.txt`,
`installers/apt/datacenter_packages.txt`,
`installers/desktop-apps/apt_packages.txt`, `installers/desktop-apps/snaps.txt`,
`installers/desktop-apps/flatpaks.txt`, `installers/flatpak/flatpaks.txt`
*(in flight: `chore/drop-flatpak-component` deletes it)*,
`installers/homebrew/brew_packages.txt`, `macos/brew.txt`,
`installers/cargo/cargo_packages.txt`. Nothing is pinned; drift is a package
renamed or dropped upstream, or one nobody wants any more (ask before
removing).

**Check APT** in a fresh container for each release the machines run (no
output means current):

```bash
docker run --rm -i -v "$PWD:/repo:ro" -w /repo ubuntu:24.04 bash -s <<'EOF'
apt-get update -qq >/dev/null
for f in installers/apt/*.txt installers/desktop-apps/apt_packages.txt; do
  sed -E 's/#.*//; s/^\?//; s/\|.*//' "$f" | awk 'NF {print $1}' | while read -r p; do
    apt-get -s -qq install "$p" >/dev/null 2>&1 || echo "$f: $p does not install"
  done
done
EOF
```

**Check Homebrew** (`/opt/homebrew/bin/brew` on the Mac):

```bash
brew=/home/linuxbrew/.linuxbrew/bin/brew
for f in installers/homebrew/brew_packages.txt macos/brew.txt; do
  sed -E 's/#.*//' "$f" | awk 'NF' | while read -r p flag; do
    "$brew" info ${flag:+--cask} "$p" >/dev/null 2>&1 || echo "$f: $p not found"
  done
done
```

**Check Cargo:** the first result for each crate must be that crate.

```bash
sed -E 's/#.*//; s/:.*//' installers/cargo/cargo_packages.txt | awk 'NF' |
  xargs -n1 ~/.cargo/bin/cargo search --limit 1
```

**Check Snap and Flathub** on an amd64 machine. Both stores filter by
architecture, so arm64 reports every amd64-only app; the installer skips those
there by design (`installers/lib/packages.sh`).

```bash
sed -E 's/#.*//; s/--classic//' installers/desktop-apps/snaps.txt | awk 'NF {print $1}' |
  while read -r s; do snap info "$s" 2>/dev/null | grep -qE '^ *latest/stable: +[^- ]' || echo "snap $s: no stable"; done
sed -E 's/#.*//' installers/desktop-apps/flatpaks.txt | awk 'NF {print $1}' |
  while read -r a; do flatpak remote-info --user flathub "$a" >/dev/null 2>&1 || echo "flathub $a: missing"; done
```

**Update:** rename or remove the entry, keeping its `# description`.

**Verify:** `bash tests/test_packages.sh`, `bash tests/test_installer_plan.sh`;
on a machine, `bash installers/installer.sh apt` (or `desktop-apps`,
`homebrew`, `cargo`).

## Downloads, repositories, and pins

Check every pass. Verify with the throwaway container where it applies.

### OpenRGB AppImage (pinned)

**Where:** `installers/openrgb/install.sh`: `OPENRGB_VERSION`,
`OPENRGB_COMMIT`, `OPENRGB_RELEASE_URL`, and a SHA-256 per architecture. The
header explains why the AppImage and not Ubuntu's package (no NVIDIA Founders
Edition illumination in the PPA build).

**Check:** WebFetch
`https://codeberg.org/api/v1/repos/OpenRGB/OpenRGB/releases?limit=3` and
compare the newest `tag_name` and AppImage names
(`OpenRGB_<version>_<arch>_<commit>.AppImage`) with the pin.

**Update:** set version and commit from the asset names, and match
`OPENRGB_RELEASE_URL` to the tag (release candidates were tagged
`release_candidate_<version>`, releases `release_<version>`). The checksums
need a download, so give the user:

```bash
for arch in x86_64 arm64; do
  curl -fsSL "https://codeberg.org/OpenRGB/OpenRGB/releases/download/<tag>/OpenRGB_<version>_${arch}_<commit>.AppImage" | sha256sum
done
```

Also re-check whether Ubuntu's package now supports the hardware; if it does,
the AppImage installer can go.

**Verify:** on a workstation, `bash installers/openrgb/install.sh`, then
`just rgb doctor`. No test covers it.

### Latest-release downloads

Unpinned: they fetch the newest release at install time, so drift shows up as
renamed assets, not version numbers.

**Where:** `installers/lazyvim/install.sh` (root path:
`nvim-linux-<arch>.tar.gz` into `/opt/nvim-linux-<arch>`),
`installers/bazelisk/install.sh` (`bazelisk-linux-<arch>`),
`installers/buildtools/install.sh` (buildifier, buildozer, unused-deps, tag
from the GitHub API).

**Check:** each prints its tag and then 2, 2, and 6 asset names.

```bash
gh api repos/neovim/neovim/releases/latest --jq '[.tag_name] + [.assets[].name | select(test("^nvim-linux-(x86_64|arm64)\\.tar\\.gz$"))] | join(" ")'
gh api repos/bazelbuild/bazelisk/releases/latest --jq '[.tag_name] + [.assets[].name | select(test("^bazelisk-linux-(amd64|arm64)$"))] | join(" ")'
gh api repos/bazelbuild/buildtools/releases/latest --jq '[.tag_name] + [.assets[].name | select(test("^(buildifier|buildozer|unused-deps)-linux-(amd64|arm64)$"))] | join(" ")'
```

**Update:** follow renamed assets in the scripts.

**Verify:** throwaway container with `bazelisk buildtools lazyvim`.

### Vendor install scripts

**Where:** the `install_from_web_script` calls (`installers/lib/common.sh`
treats the command on `PATH`, with `~/.local/bin` prepended, as installed):
`installers/uv/install.sh`, `installers/tailscale/install.sh`,
`installers/opencode/install.sh`, `installers/claude/install.sh`,
`installers/codex/install.sh` (`CODEX_NON_INTERACTIVE=1`),
`installers/grok/install.sh` (binary in `~/.grok/bin`),
`installers/agy/install.sh`, `installers/ollama/install.sh`,
`installers/zoxide/install.sh`, and *(in flight: `feat/herdr-installer`)*
`installers/herdr/install.sh`, `installers/herdr-core/install.sh`. Also
Homebrew (`installers/homebrew/install.sh`, `NONINTERACTIVE=1`) and rustup
(`installers/cargo/install.sh`, `-y --profile minimal --no-modify-path`).

**Check:** the vendor docs linked in each script's header still give the same
URL, binary name, install location, and flags, and have not moved to another
install method (as Codex moved from npm to its standalone installer).

**Update:** change the URL, name, or flags.

**Verify:** throwaway container with the component;
`bash tests/test_install_steps.sh`.

### Third-party APT repositories

**Where:**

- Docker: `installers/docker/install.sh`. Key, deb822 source per Ubuntu
  codename, `DOCKER_PACKAGES`, and `CONFLICTING_PACKAGES`, a copy of the
  "Uninstall old versions" list on `https://docs.docker.com/engine/install/ubuntu/`.
- NVIDIA Container Toolkit: same file. Key and flat repository under
  `https://nvidia.github.io/libnvidia-container/`, then `nvidia-ctk runtime configure`.
- RealSense: `installers/robotics/install.sh`. Key, repository, codename
  allowlist, package set, DKMS on amd64 only.
- NodeSource: `installers/lazyvim/install.sh` root path (`setup_lts.x`).
- PPAs: manifests may add one with `package | ppa:user/repo`
  (`git grep -n 'ppa:' installers/apt installers/desktop-apps`).

**Check:** compare each with the vendor's current Ubuntu instructions (links in
the script headers). For each codename the machines run, the repository must
publish it: WebFetch
`https://download.docker.com/linux/ubuntu/dists/<codename>/Release` and
`https://librealsense.realsenseai.com/Debian/apt-repo/dists/<codename>/Release`
(the directory listings are forbidden; the `Release` files are not), and read
their `Architectures`.

**Update:** mirror the vendor docs; add published codenames to the RealSense
allowlist.

**Verify:** on a GPU workstation, `bash installers/installer.sh docker robotics`,
then `docker run --rm --gpus all ubuntu nvidia-smi` and `realsense-viewer`.

### tmux plugins

**Where:** `installers/tmux/install.sh` clones tmux-resurrect and
tmux-continuum and fast-forwards them on every run, so they follow upstream.
The repo works around their internals, explained in `installers/tmux/install.sh`
and `tmux/tmux.conf`: continuum's systemd unit (its `ExecStop` save after an
OOM kill), continuum's save job in `status-right`, and `save.sh` writing an
empty frame when no server answers.

**Check:** read upstream commits since the last pass for changes to those
paths:

```bash
for p in tmux-resurrect tmux-continuum; do
  gh api "repos/tmux-plugins/$p/commits?per_page=10" \
    --jq ".[] | \"$p \" + .commit.committer.date[:10] + \" \" + (.commit.message | split(\"\n\")[0])"
done
```

**Update:** adjust the workaround, or delete it if upstream fixed the cause.

**Verify:** `bash tests/test_tmux_install.sh`, `bash tests/test_agent_tmux.sh`,
`python3 tests/test_tmux_osc52.py`.

### LazyVim and Neovim plugins

**Where:** `installers/lazyvim/install.sh` clones `LazyVim/starter` once
(detected by `lua/config/lazy.lua`) and installs the Nerd Font cask
`font-jetbrains-mono-nerd-font` (family `JetBrainsMono Nerd Font Mono`).
`installers/lazyvim/plugins/vim-tmux-navigator.lua` names the plugin's
commands; `installers/lazyvim/plugins/url-underline.lua` names Tree-sitter
captures `@string.special.url` and `@markup.link.url`.

**Check:**

```bash
gh api repos/LazyVim/starter/contents/lua/config/lazy.lua --jq .path
brew info --cask font-jetbrains-mono-nerd-font | head -1
gh api -H 'Accept: application/vnd.github.raw' repos/nvim-treesitter/nvim-treesitter/contents/CONTRIBUTING.md |
  grep -E '@string\.special\.url|@markup\.link\.url'
```

On a workstation, `nvim` then `:LazyHealth` shows no errors.

**Verify:** `bash tests/test_lazyvim_font.sh`, `bash tests/test_nvim_config.sh`.

## Copied from upstream

### tmux snippets

**Where:** `tmux/tmux.conf`. Its last line is tmux's default `status-right`,
re-set so continuum's save job is dropped. The `vim_pattern` and `is_vim`
lines are vim-tmux-navigator's README snippet. Its comments also rely on mosh
1.4 forwarding only OSC 0/1/2/8/52, and on tmux 3.3+ needing
`allow-passthrough`.

**Check:** run the first command with each tmux a machine has (apt's
`/usr/bin/tmux` and Homebrew's); its output must equal the `status-right` line.
The README snippet must equal ours.

```bash
tmux -L maintenance -f /dev/null start-server \; show-options -gv status-right
grep '^set -g status-right' tmux/tmux.conf
gh api -H 'Accept: application/vnd.github.raw' repos/christoomey/vim-tmux-navigator/contents/README.md |
  grep -m2 -A1 -E '^(vim_pattern|is_vim)='
```

**Update:** copy upstream's text. On a new mosh release, re-check its OSC
forwarding before trusting the comments.

**Verify:** `bash tests/test_agent_tmux.sh`, `python3 tests/test_tmux_osc52.py`.

Other copies have their own items: the Docker conflict list (Third-party APT
repositories), AeroSpace's default config (macOS app config), and the Herdr
layout and mod (below).

## Herdr

*(in flight: `feat/herdr-installer` adds `herdr/`, the Herdr installers, and
their tests; `scripts/agent-session` and `skills/session/SKILL.md` are on
`origin/main`.)*

Check on each Herdr release. The version the copies track is
`cloned_from.version` in `herdr/layouts/agent-tree.json`. Set up once per pass:

```bash
scratch=$(mktemp -d)
git clone -q --filter=blob:none https://github.com/herdrdev/herdr-app "$scratch/herdr-app"
old=v$(jq -r .cloned_from.version herdr/layouts/agent-tree.json)
new=$(gh api repos/herdrdev/herdr-app/tags --jq '.[0].name')
git -C "$scratch/herdr-app" diff --stat "$old..$new" -- defaults/
```

Nothing to do when `$new` equals `$old`. The repo's default branch is
`master`.

### Agent-tree layout

**Where:** `herdr/layouts/agent-tree.json` is a copy of Herdr's
`defaults/layouts/main.json` at `cloned_from.version`, with the `agents`
block's `content.mod` changed to `agent-tree` and `cloned_from` added. Herdr
never updates copies. The user chose to keep this fixed copy rather than
generate it.

**Check:** `git -C "$scratch/herdr-app" diff "$old..$new" -- defaults/layouts/main.json`

**Update:** copy `main.json` at `$new` again, reapply the `content.mod` change,
and set `cloned_from` to `{"name": "main", "version": "<new without v>"}`.
Update the version named in `herdr/README.md`.

**Verify:** prints `matches upstream`.

```bash
git -C "$scratch/herdr-app" show "$new:defaults/layouts/main.json" > "$scratch/main.json"
python3 -I - "$scratch/main.json" herdr/layouts/agent-tree.json <<'EOF'
import json, sys
upstream, ours = (json.load(open(path)) for path in sys.argv[1:])
ours.pop("cloned_from")
def restore(node):
    if node.get("id") == "agents":
        node["content"]["mod"] = "agents"
    for child in node.get("children", []):
        restore(child)
restore(ours)
print("matches upstream" if ours == upstream else "differs beyond the agents mod")
EOF
```

### Agent-tree mod

**Where:** `herdr/mods/agent-tree/main.js` and `herdr/mods/agent-tree/tree.js`
copy behavior from Herdr's shipped `defaults/mods/agents/main.js`: status
marks, title cleaning, time in state, the narrow sidebar rail and its toggle.
They target the mod API in `defaults/herdr.d.ts` (the `gpui-kit`, `gpui-base`,
and `herdr` modules); `tests/herdr_agent_tree.mjs` stands in for those modules
under node.

**Check:**

```bash
git -C "$scratch/herdr-app" diff "$old..$new" -- defaults/mods/agents/ defaults/herdr.d.ts defaults/AGENTS.md
```

**Update:** port what changed into the mod, and API changes into the stand-ins
in `tests/herdr_agent_tree.mjs`.

**Verify:** `bash tests/test_herdr_agent_tree.sh` (needs node). After the app
updates, on the Mac where it runs:
`herdr-app check ~/.config/herdr-app/mods/agent-tree`.

### Herdr installers

**Where:** `installers/herdr/install.sh` (binary `herdr-app`),
`installers/herdr-core/install.sh` (binary `herdr-core`, CLI `hc`),
`installers/config/herdr.sh` (app home: `HERDR_APP_HOME`, else
`$XDG_CONFIG_HOME/herdr-app`, else `~/.config/herdr-app`).

**Check:** the install sections of the herdr-app and herdr-core READMEs, and
the app-home lookup in `defaults/AGENTS.md`.

**Verify:** `bash tests/test_herdr_install.sh`.

### hc contract

**Where:** `scripts/agent-session`, `skills/session/SKILL.md`, and the stub hc
in `tests/test_agent_session.py`. They rely on `hc get --json`, `hc ls --json`,
`hc exec`, `hc run --bg --json --no-parent --name --cwd --on --label`,
`hc machine ls`, `hc send`, `hc read`, `$HC_TERMINAL_ID`, the labels
`herdr.space`, `herdr.tab`, and `where`, `foreground.argv`, and the `blocked`
status.

**Check:** compare `hc --version` with
`gh api repos/herdrdev/herdr-core/tags --jq '.[0].name'`, read `hc run --help`
and `hc get --help` for those flags, and diff herdr-core between the two
versions for label or JSON changes.

**Update:** follow hc in the script, the skill, and the stub together.

**Verify:** `python3 tests/test_agent_session.py`; start a session with the
`session` skill from a Herdr terminal.

## Ubuntu releases

Check when Ubuntu ships a release the machines will run, or when the user
drops one. `ubuntu-distro-info --supported --fullname` lists what is
supported; ask the user which releases their machines run. Run the APT check
(Package manifests) and the throwaway container on the new release first.
Each item below is code written for a particular release:

- **Codex AppArmor profile**, `installers/codex/install.sh`. Ubuntu 24.04+
  sets `kernel.apparmor_restrict_unprivileged_userns=1`, so the script loads
  `bwrap-userns-restrict` from apparmor-profiles' extra profiles for Codex's
  bubblewrap sandbox. On a new release, confirm the package still ships it and
  Ubuntu does not already load an equivalent:
  `docker run --rm ubuntu:<release> bash -c 'apt-get update -qq && apt-get install -y -qq apparmor-profiles >/dev/null && ls /usr/share/apparmor/extra-profiles/ /etc/apparmor.d/ | grep -i bwrap'`.
  Delete the block when Ubuntu loads one itself or Codex stops using
  bubblewrap; drop the 22.04 sentence when 22.04 goes. Verify on a 24.04+
  machine: `bash installers/codex/install.sh` reports the profile loaded, and
  Codex runs a sandboxed command.
- **libfuse2**, `installers/apt/apt_packages.txt` and `missing_apt_packages` in
  `installers/lib/packages.sh`. The manifest uses the 22.04 name; 24.04 renamed
  it libfuse2t64, which provides libfuse2. When 22.04 goes, list libfuse2t64
  and delete the virtual-name branch if nothing else needs it. Verify:
  `bash tests/test_packages.sh`.
- **RealSense codenames**, the `case` in `installers/robotics/install.sh`. An
  unlisted codename only warns. Add each codename the repository publishes
  (see Third-party APT repositories) and note that DKMS is amd64-only.
- **GNOME dock**, `hidden_favorites` in `installers/config/gnome.sh`: Help and
  App Center desktop IDs. On a fresh desktop of the release,
  `gsettings get org.gnome.shell favorite-apps`. Verify:
  `bash tests/test_gnome_config.sh`.
- **Terminal**, `configure_gnome_terminal_font` in
  `installers/lazyvim/install.sh` and `theme_mode` in `.bash_aliases`
  (GNOME Terminal profile UUIDs) configure GNOME Terminal through
  `org.gnome.Terminal.*`. If the release's default terminal is another (Ptyxis
  on recent Ubuntu desktops), both configure nothing; ask whether to retarget.
  `ducky/payloads/ubuntu-install.txt` opens a terminal with Ctrl+Alt+T.
- **CPU power**, `installers/config/power.sh`: power-profiles-daemon
  (`powerprofilesctl`, D-Bus `net.hadess.PowerProfiles`), else cpufrequtils
  (`/etc/default/cpufrequtils`, `cpufrequtils.service`) and sysfs. On the
  release, `powerprofilesctl list` shows a `CpuDriver:` line on desktops.
  Verify: `DRY_RUN=true bash installers/config/power.sh`.
- **SSH server**, `installers/config/ssh.sh`: `/usr/sbin/sshd`,
  `/etc/ssh/sshd_config.d/`, and `ssh.service` (Ubuntu socket-activates sshd
  through `ssh.socket` by default). Verify on a machine: sync config, then
  `sudo sshd -t` and a key login.
- **NVIDIA driver**, `installers/nvidia-driver/install.sh` parses
  `ubuntu-drivers devices`. On a GPU machine this prints exactly one package:
  `LC_ALL=C ubuntu-drivers devices | awk '$1 == "driver" && $3 ~ /^nvidia-driver-/ && / recommended *$/ { print $3 }'`.
  Verify: `bash tests/test_nvidia_driver.sh`.
- **ROS**, `alias shumble` in `.bash_aliases` sources ROS 2 Humble, the ROS for
  22.04. Ask whether to point it at the release's ROS 2 distribution.

## Transition code

Shims that migrate machines from an old layout. Each can be deleted, with any
test of it, once every machine the user maintains has run it. Ask the user
which machines those are, and have this probe run on each; it prints only
leftovers, and a machine that prints nothing has migrated:

```bash
ls -d /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  /usr/local/lib/linux-utils/openrgb ~/.claude/scripts ~/.codex/scripts ~/.grok/scripts \
  ~/.local/share/nvim/mason/packages/tree-sitter-cli ~/.local/bin/upkeep 2>/dev/null
find ~/.agents/skills ~/.claude/skills ~/.gemini/config/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null
grep -n max_threads ~/.codex/config.toml 2>/dev/null
grep -q 'zoxide init bash' ~/.bashrc 2>/dev/null &&
  ! grep -Fq '":$HOME/.local/bin:"' ~/.bashrc && echo "zoxide PATH line missing"
```

The shims, with the commit that added each (`git log -S '<name>'`):

- Retired GitHub CLI APT source: `retired_gh_sources` in
  `installers/installer.sh`, since #87.
- Legacy OpenRGB payload: `LEGACY_SYS_LIB` in `installers/openrgb/install.sh`,
  since #59 (workstations with OpenRGB only).
- Per-tool script directories: the `remove_stale_path` calls in
  `installers/config/agents.sh`, since #94.
- `upkeep` link: `remove_stale_path "$HOME/.local/bin/upkeep"` in
  `installers/config/bash.sh`, since #148 renamed the command to `resync`.
- Per-file skill links: the `is_repo_link_tree` branch of `apply_skill_links`
  in `installers/config/lib.sh`, since #42. The loop that removes links to
  renamed skills stays.
- Codex `max_threads`: the legacy-alias special case in `scripts/inject-config`,
  since #29. Its test is in `tests/test_inject_config.py`.
- zoxide PATH line: the branch of `installers/zoxide/install.sh` that inserts
  the PATH line above an existing `zoxide init`, since #82. Its test is in
  `tests/test_zoxide_init.sh`.
- Mason's Tree-sitter CLI: `remove_shadowed_treesitter_cli` in
  `installers/lazyvim/install.sh`, since #82. Mason reinstalls it whenever a
  plugin asks, so confirm LazyVim no longer asks before deleting.

**Verify:** `bash tests/run.sh`.

## This file

**Check:** every repo path named here exists. Paths from in-flight branches
show as missing until they merge.

```bash
grep -oE '`[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+`' MAINTENANCE.md | tr -d '`' | sort -u |
  while read -r p; do [ -e "${p%%/*}" ] && [ ! -e "$p" ] && echo "missing: $p"; done
```

**Update:** when an item stops applying (a component, copy, or shim removed),
delete it. When a change adds something that drifts on its own (a pin, an
upstream copy, a release workaround, a shim), add its item in the same PR.

**Verify:** `~/.local/bin/uvx pre-commit run --files MAINTENANCE.md`.
