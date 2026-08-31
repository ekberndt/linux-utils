# macOS

`just install` detects Darwin and runs this installer. It installs the Homebrew
packages in [`brew.txt`](brew.txt) and agent config: skills, AeroSpace
(`~/.aerospace.toml`), editor, and tmux. Agent config still runs if Homebrew
is missing or a formula fails. An existing AeroSpace configuration is
timestamp-backed up before the link is created.

`just config` skips Homebrew and only resyncs that config.

Install [Homebrew](https://brew.sh), then `just install`.

AeroSpace itself is not installed by the script because its third-party tap
requires an explicit Homebrew trust decision. Install it separately, then rerun
config sync to manage its configuration from this repository:

```bash
brew trust nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace
```
