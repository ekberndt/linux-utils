# macOS

`just install` detects Darwin and runs this installer. It installs the Homebrew
packages in [`brew.txt`](brew.txt), upgrades everything Homebrew holds and
every cross-platform component already installed (uv, the agent CLIs, zoxide,
Rust and Cargo, LazyVim, global npm, pnpm, pip, and pipx packages), and installs agent
config: skills, AeroSpace
(`~/.aerospace.toml`), Warp OSC 52 clipboard access (`~/.warp/settings.toml`),
editor, and tmux. Agent config still runs if Homebrew is missing or a formula
fails. An existing AeroSpace configuration is timestamp-backed up before the
live file is written. Warp settings are merged: the tracked OSC 52 key wins, and
every other Warp preference stays.

App-to-workspace assignments are not tracked. Copy
[`app-workspaces.cfg.example`](app-workspaces.cfg.example) to
`app-workspaces.cfg` (gitignored) and run `just config`.
[`scripts/aerospace-workspaces`](../scripts/aerospace-workspaces) loads that
map into `~/.aerospace.toml`.

Both `just install` and `just config` create `~/Pictures/screenshots/` and set
it as the screenshot save location.

`just config` skips Homebrew and resyncs these settings.

Warp denies OSC 52 by default, so copies from a remote tmux session never
reach the macOS clipboard. Config sync sets `osc52_clipboard_access =
"read_write"`. The Linux tmux config emits the sequence; this is the Mac
half that accepts it.

Install [Homebrew](https://brew.sh), then `just install`.

AeroSpace (and optional [JankyBorders](https://github.com/FelixKratz/JankyBorders)
focused-window borders) are not installed by the script because their third-party
taps require explicit Homebrew trust decisions. Install them separately, then
rerun config sync to manage AeroSpace's configuration from this repository:

```bash
brew trust nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace

# Optional: colored border on the focused window (started by AeroSpace on launch)
brew tap FelixKratz/formulae
brew trust FelixKratz/formulae
brew install FelixKratz/formulae/borders
```
