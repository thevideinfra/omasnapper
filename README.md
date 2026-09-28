# snapper

A bar widget + panel for [Omarchy 4](https://omarchy.org/) that makes your Btrfs/Snapper snapshots visible and manageable. Omarchy takes a snapshot before every update, but until now there was no desktop UI for them — snapshots silently eat disk until something breaks. This fixes that.

## What it does

- **Bar pill** shows how much disk your snapshots exclusively use (e.g. `󰁯 2.3G`), with a `!` when it passes your warning threshold. Without btrfs quotas it shows the snapshot count instead.
- **Panel** lists every snapshot across your snapper configs: number, type (single/pre/post), date, description, per-snapshot exclusive size.
- **Snapshot now** — one click, timestamped description, number-cleanup class so retention policies apply.
- **Clean up** — runs snapper's number-based cleanup on the spot (same thing `omarchy-snapshot create` runs after every update).
- **Delete** — two-step confirm, per snapshot.
- **Restore…** — opens a terminal running Omarchy's own `sudo limine-snapper-restore`, where you pick the snapshot (interactive, preserves `/home`).
- **Quota helper** — per-snapshot sizes need btrfs quotas; if they're off, the panel offers to enable them.

Boot entries for snapshots appear automatically in the Limine boot menu via `limine-snapper-sync` — no action needed.

## Requirements

- Omarchy 4 (Quickshell "quattro" shell)
- `snapper` + a btrfs root (standard on Omarchy installs)
- Your user in the snapper config's `ALLOW_USERS`, so status, create, delete and cleanup run through snapperd without a password:

  ```bash
  sudo snapper -c root set-config ALLOW_USERS="$USER"
  ```

- `pkexec` for the one root-only action, enabling btrfs quotas

## Install

```bash
omarchy plugin add https://github.com/thevideinfra/snapper.git --enable
```

The widget lands in the right section of the bar. Move it with:

```bash
omarchy bar move videinfra.snapper --section right
```

## Configure

Settings UI, or inline in `~/.config/omarchy/shell.json` on the widget entry:

| Key | Type | Default | What |
|---|---|---|---|
| `refreshIntervalSec` | integer | 300 | How often the bar pill refreshes (60–3600) |
| `showSizes` | boolean | true | Show exclusive disk usage in the pill (needs quotas) |
| `confirmDelete` | boolean | true | Two-step confirmation before deleting |
| `warnThresholdGB` | integer | 5 | Pill shows `!` past this much snapshot disk use |

```bash
omarchy bar set videinfra.snapper warnThresholdGB --json 10
```

## How it works

- `BarWidget.qml` runs `bin/snapper-helper status` on a timer and renders the pill. Clicking toggles `Panel.qml`.
- `bin/snapper-helper` (python3) runs as you and talks to snapperd through `snapper --jsonout`, with fixed argv — never interpolated shell strings — and prints one JSON document. Per-snapshot sizes come from snapper's `used-space` column, which snapper fills in only while btrfs quotas are on. Snapshot descriptions are rendered as plain text, never as markup.
- Mutations (`create`, `delete <config> <number>`, `cleanup`) run through the same helper. Only `quota-enable` goes through `pkexec`.
- The panel also answers IPC: `qs ipc -p "$OMARCHY_PATH/shell" call videinfra.snapper toggle`.
- Restore deliberately does **not** run headless: it opens `foot` with `sudo limine-snapper-restore`, the same interactive tool `omarchy snapshot restore` uses.

## Remove

```bash
omarchy plugin remove videinfra.snapper
```

Removes only the plugin. Snapshots, snapper configs, and quotas are untouched.

## Development

```bash
omarchy plugin validate /path/to/snapper
omarchy plugin add /path/to/snapper --enable   # local path also works
omarchy-restart-shell
qs log -p "$OMARCHY_PATH/shell" --tail 100               # QML errors
```

Run the helper tests (they use a stub `snapper` on `PATH`):

```bash
python3 -m unittest discover -s tests
```

## Notes / limitations

- Snapshots live on the same disk as the system. This is an undo button, not a backup.
- Per-snapshot sizes require btrfs quotas (`btrfs quota enable /`); there's a small ongoing accounting cost, which is why it's opt-in via the panel button.
- `timeline` snapshots aren't created by Omarchy's config (`TIMELINE_CREATE=no`); cleanup covers the `number` class only, matching `omarchy-snapshot`.
- Plugin code is unsandboxed by design in Omarchy — only install plugins from sources you trust, including this one. Review `bin/snapper-helper` if you like; it's short.
