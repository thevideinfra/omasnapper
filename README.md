# omasnapper

A bar widget and panel for [Omarchy 4](https://omarchy.org/) that shows your Btrfs system snapshots, says why each one exists, and lets you take, delete and restore them without a terminal.

Omarchy takes a snapshot before every update. Until now there was no desktop UI for them.

## What it does

- **Bar pill** shows the snapshot count (`󰁯 4`). With btrfs quotas on, it shows the space snapshots hold instead, with a `!` past your warning threshold.
- **Snapshot list** says who made each snapshot and why. Times follow the bar clock's 12- or 24-hour format.
  - *Before Omarchy update* — the Omarchy version at the time and what that update changed, read from `/var/log/pacman.log`, e.g. `4.0.4 → 4.0.5 · 30 updated, 2 added`. Select the snapshot to see each package; that list is what restoring it undoes.
  - *Manual snapshot* — taken from this panel, with the user who took it.
  - *Safety copy before restore* — the system as it was before a restore.
- **Snapshot now** — asks for a name first (blank uses "Manual snapshot"), or takes the snapshot in one click when "Name snapshots before taking them" is off in settings.
- **Restore** — select a snapshot, confirm, enter your password. The restore runs in the background and the panel then offers a reboot. It rolls back the system subvolume only; `/home` is untouched, and the current system is kept as a safety copy.
- **Delete** — select a snapshot and confirm.
- **Pin** — keep a snapshot out of auto-delete (clears its snapper cleanup class). Pinned rows show 󰐃.
- **Rename** — edit a snapshot's description in place; Enter saves.
- **Files** — list the files that differ between the snapshot and now (`snapper status N..0`).
- **Folder** — open the snapshot's read-only folder, e.g. `/.snapshots/9/snapshot`. The first time, it asks to let your user read `/.snapshots` (snapper's `SYNC_ACL`).
- **Retention** — how many snapshots to keep, whether older ones are deleted automatically, and scheduled snapshots (off, daily or hourly). Before you apply, the panel names every snapshot the change deletes. Applying takes your password, writes the snapper config, prunes right away, and turns `snapper-timeline.timer` on or off. It also raises the Limine boot menu's `MAX_SNAPSHOT_ENTRIES` in `/etc/limine-entry-tool.d/zz-omasnapper.conf` so every kept snapshot stays restorable. The section can be hidden in settings.
- **Settings** (gear) — density, font size, show or hide retention, allow browsing snapshot folders, and enabling btrfs quotas for per-snapshot sizes.

There is no cleanup button: snapper's hourly `snapper-cleanup.timer` and Omarchy's updater already prune to the retention limit, and applying a lower limit prunes at once.

Snapshots also appear in the Limine boot menu through `limine-snapper-sync`.

## Requirements

- Omarchy 4 (Quickshell "quattro" shell)
- `snapper`, `limine-snapper-sync` and a btrfs root (standard on Omarchy installs)
- Your user in the snapper config's `ALLOW_USERS`, so listing, creating and deleting snapshots needs no password:

  ```bash
  sudo snapper -c root set-config ALLOW_USERS="$USER"
  ```

- `pkexec` for the root-only actions: restore, applying retention, allowing browsing and enabling quotas

## Install

```bash
omarchy plugin add https://github.com/thevideinfra/omasnapper.git --enable
```

For a local checkout, link it into `~/.config/omarchy/plugins/videinfra.omasnapper` and run `omarchy plugin enable videinfra.omasnapper`. Restart the shell after QML edits, since linked plugins do not hot reload.

## Configure

Use the gear in the panel, the settings UI, or inline in `~/.config/omarchy/shell.json`:

| Key | Type | Default | What |
|---|---|---|---|
| `density` | enum | normal | compact, normal or comfortable |
| `fontSize` | enum | normal | small, normal or large |
| `refreshIntervalSec` | integer | 300 | How often the bar pill refreshes (60–3600) |
| `warnThresholdGB` | integer | 5 | Pill shows `!` past this much snapshot space (needs quotas) |

The panel also answers IPC: `qs ipc -p "$OMARCHY_PATH/shell" call videinfra.omasnapper toggle`.

## How it works

- `Panel.qml` is the bar widget and the panel. It runs `bin/omasnapper-helper` and renders its JSON.
- `bin/omasnapper-helper` (python3) runs as you for `status`, `create` and `delete`, and talks to snapperd through `snapper --jsonout`. It always passes a fixed argv, never a shell string.
- `restore` runs the helper as root through `pkexec`. The helper starts Omarchy's own `limine-snapper-restore` in a hidden pseudo-terminal and answers its two questions: which snapshot, and a description for the safety copy. If the tool asks anything else (a snapshot that fails file verification, a snapshot missing from the boot menu), the helper cancels, and nothing is restored.
- Per-snapshot sizes come from snapper's `used-space` column, which snapper fills in only while btrfs quotas are on.

## Remove

```bash
omarchy plugin remove videinfra.omasnapper
```

This removes only the plugin. Snapshots, snapper configs and quotas stay as they are.

## Development

```bash
npm test    # node tests for Model.js, python tests for bin/omasnapper-helper
omarchy plugin validate .
qs log -p "$OMARCHY_PATH/shell" --tail 100    # QML errors
```

The restore tests drive `tests/fake_limine_restore.py`, which asks the same prompts as the real tool, so they never touch the system.

## Notes

- Snapshots live on the same disk as the system. They are an undo button, not a backup.
- Deleting a snapshot frees only the data that snapshot alone holds. That is often small, because most of it is shared with the running system. Btrfs also frees space in the background, so the free-space figure can lag.
- Omarchy keeps its update snapshots to 5 (`NUMBER_LIMIT=5`) and prunes older ones after each update.
- Omarchy's snapper setup (`install/config/snapper.sh`) rewrites the snapper config from its template. If it runs again, it resets retention and drops `ALLOW_USERS`; the panel then says which command restores access.
- Plugin code is unsandboxed by design in Omarchy. Only install plugins you trust, including this one. `bin/omasnapper-helper` is short; read it before granting it root for a restore.
