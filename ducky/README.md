# USB Rubber Ducky — linux-utils bootstrap

Payload for **Ubuntu** desktops (GNOME). The machine you use to flash (macOS here is fine) only loads `inject.bin` onto the Ducky; it is not a target.

Plugging the Ducky into a logged-in Ubuntu session clones this repo and runs the `workstation` installer profile.

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

Default clone URL: `https://github.com/ekberndt/linux-utils.git` → `~/src/linux-utils`.

## Flash (arming / any host with this repo)

With the Ducky plugged in so it mounts as storage:

```bash
just ducky-flash
# or:
bash ducky/flash.sh
# or a custom payload:
bash ducky/flash.sh ducky/payloads/ubuntu-install.txt
```

Eject, unplug, then use on Ubuntu:

```bash
diskutil eject /Volumes/DUCKY   # macOS flash host
# umount /media/$USER/DUCKY    # Linux flash host
```

On the **Ubuntu** box: plug in while logged into a desktop session. When `sudo` asks for a password, type it. The installer runs non-interactively after that.

## Layout / encoder

- `encode.py` is a **classic DuckyScript 1.0** encoder for the **US** keyboard layout. It does not need Payload Studio or Java.
- Payload source: `payloads/ubuntu-install.txt`
- Built binary: `build/inject.bin` (also copied to the stick as `inject.bin`)
- The stick also gets `payload.txt` (copy of the source) for inspection

If the target uses a non-US layout, either switch the OS layout to US for the run or re-encode with [Payload Studio](https://payloadstudio.hak5.org) / [encoder.hak5.org](https://encoder.hak5.org) using the same `.txt` source.

## Customize

Edit `payloads/ubuntu-install.txt`:

| Want | Change |
| --- | --- |
| Different repo URL | `REPO_URL=...` inside the heredoc |
| Clone path | `DEST=...` |
| Installer targets | `bash installers/installer.sh workstation` → e.g. `uv cargo config` |
| Non-GNOME terminal | Replace `CTRL-ALT t` with whatever opens a shell on that DE |

Re-flash after edits: `just ducky-flash`.

## Safety

This injects keystrokes on whatever machine you plug into. Only use on machines you own or are authorized to configure. The Ducky will fire as soon as the host accepts a keyboard — close the session or unplug if you arm it by mistake.
