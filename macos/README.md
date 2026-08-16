# macOS

The macOS installer installs the Homebrew packages in [`brew.txt`](brew.txt)
and links the tracked AeroSpace configuration to `~/.aerospace.toml`. An
existing AeroSpace configuration is timestamp-backed up before the link is
created.

Install [Homebrew](https://brew.sh), then run from the repository root:

```bash
bash macos/install.sh
```

AeroSpace itself is not installed by the script because its third-party tap
requires an explicit Homebrew trust decision. Install it separately, then rerun
the installer to manage its configuration from this repository:

```bash
brew trust nikitabobko/tap
brew install --cask nikitabobko/tap/aerospace
```
