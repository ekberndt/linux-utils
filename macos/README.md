# macOS

`just install` detects Darwin and runs this installer. It installs the Homebrew
packages in [`brew.txt`](brew.txt) and agent config: skills, AeroSpace
(`~/.aerospace.toml`), Warp OSC 52 clipboard access (`~/.warp/settings.toml`),
editor, and tmux. Agent config still runs if Homebrew is missing or a formula
fails. An existing AeroSpace configuration is timestamp-backed up before the
link is created. Warp settings are merged: the tracked OSC 52 key wins, and
every other Warp preference stays.

`just config` skips Homebrew and only resyncs that config.

Warp denies OSC 52 by default, so copies from a remote tmux session never
reach the macOS clipboard. Config sync sets `osc52_clipboard_access =
"read_write"`. The Linux tmux config emits the sequence; this is the Mac
half that accepts it.

Install [Homebrew](https://brew.sh), then `just install`.

AeroSpace itself is not installed by the script because its third-party tap
requires an explicit Homebrew trust decision. Install it separately, then rerun
config sync to manage its configuration from this repository:

```bash
brew trust nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace
```
