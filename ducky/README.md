# USB Rubber Ducky — linux-utils bootstrap

Payload for **Ubuntu** desktops (GNOME). The machine you use to flash (macOS here is fine) only loads `inject.bin` onto the Ducky; it is not a target.

Plugging the Ducky into a logged-in Ubuntu session creates or updates a local
user (sudo, password, SSH key), clones this repo into that user's
`~/src/linux-utils` (or fast-forwards `main` on an existing clone, same as
`linux-utils-install`), and runs the `workstation` installer profile.

Username, full name, password, and SSH public key are collected at flash time
and exist only in memory and on that stick. They are not stored in this repo.

## Host vs target

| Role | OS | What happens |
| --- | --- | --- |
| **Flash host** | macOS or Linux (this repo checkout) | Ducky in arming mode → `just ducky-flash` writes `inject.bin` |
| **Target** | Ubuntu desktop, logged in, network up | Ducky types the bootstrap; you enter sudo when prompted |

Do not expect the payload to do anything useful on macOS — `Ctrl+Alt+T`, `apt-get`, and the installer are Ubuntu-only.

## How it works

1. **Arming mode** (Ducky mounted as a small FAT volume, usually labeled `DUCKY`): write `inject.bin` from the flash host.
2. **Attack mode** (normal plug-in on Ubuntu): the Ducky acts as a keyboard and types the payload.
3. Opens a GNOME terminal (`Ctrl+Alt+T`), writes `/tmp/linux-utils-bootstrap.sh`, then runs it. The install script is written fully before any `sudo` prompt so password entry is not corrupted by leftover keystrokes.

On the target, the bootstrap feeds the flashed password to `sudo -S` (no extra
keystrokes after the script starts). It creates the user if missing, sets that
password and `sudo`, and appends the public key to `~/.ssh/authorized_keys`.
The clone and workstation install then run as that user.

Default clone URL: `https://github.com/ekberndt/linux-utils.git` → `~/src/linux-utils` of the flashed user, then `origin/main`.

## Flash (arming / any host with this repo)

Plug the Ducky in **without holding the button**, then press the button once so
it mounts as storage. Holding the button while inserting enters Atmel DFU
(`03eb:2ff6`), which cannot take a payload; Ubuntu `fwupd` can also stick it
there — reset with `sudo dfu-programmer at32uc3b1512 reset`.

```bash
just ducky-flash
# or:
bash ducky/flash.sh
```

`flash.sh` runs a Claude Code-style setup: username, full name, password, then
an SSH public key (`↑↓` through `~/.ssh/*.pub`, or type/paste a path).

Or set `DUCKY_USERNAME`, `DUCKY_FULLNAME`, `DUCKY_PASSWORD`, and
`DUCKY_PUBKEY_FILE` in the environment instead of answering prompts. Those
values are not written to the checkout; only `inject.bin` is copied to the
stick.

Eject, unplug, then use on Ubuntu:

```bash
diskutil eject /Volumes/DUCKY   # macOS flash host
# umount /media/$USER/DUCKY    # Linux flash host
```

On the **Ubuntu** box: plug in while logged into a desktop session, without
holding the button. When `sudo` asks, type the logged-in user's password first;
the installer may then ask for the flashed user's password. The rest runs
non-interactively.

## Layout / encoder

- `encode.py` is a **classic DuckyScript 1.0** encoder for the **US** keyboard layout. It does not need Payload Studio or Java.
- Payload source: `payloads/ubuntu-install.txt` (no identity secrets)
- The stick receives only `inject.bin`

If the target uses a non-US layout, either switch the OS layout to US for the run or re-encode with [Payload Studio](https://payloadstudio.hak5.org) / [encoder.hak5.org](https://encoder.hak5.org) using the same `.txt` source. Passwords and keys must be typeable on a US keyboard.

## Customize

Edit `payloads/ubuntu-install.txt`:

| Want | Change |
| --- | --- |
| Different repo URL | `REPO_URL=...` inside the heredoc |
| Installer targets | `bash installers/installer.sh workstation` → e.g. `uv cargo config` |
| Non-GNOME terminal | Replace `CTRL-ALT t` with whatever opens a shell on that DE |

Re-flash after edits: `just ducky-flash`.

## Safety

This injects keystrokes on whatever machine you plug into. Only use on machines you own or are authorized to configure. The Ducky will fire as soon as the host accepts a keyboard — close the session or unplug if you arm it by mistake.
