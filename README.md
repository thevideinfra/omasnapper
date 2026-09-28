# snapper

A bar widget + panel for [Omarchy 4](https://omarchy.org/) that makes your Btrfs/Snapper snapshots visible and manageable. Omarchy takes a snapshot before every update, but until now there was no desktop UI for them — snapshots silently eat disk until something breaks. This fixes that.

## What it does

- **Bar pill** shows how much disk your snapshots exclusively use (e.g. `󰁯 2.3G`), with a `!` when it passes your warning threshold. Without btrfs quotas it shows the snapshot count instead.
- **Panel** lists every snapshot across your snapper configs: number, type (single/pre/post), date, description, per-snapshot exclusive size.
- **Snapshot now** — one click, timestamped description, number-cleanup class so retention policies apply.
- **Clean up** — runs snapper's number-based cleanup on the spot (same thing `omarchy-snapshot create` runs after every update).
- **Delete** — two-step confirm, per snapshot.
- **Restore** — two-step confirm, then opens a terminal running Omarchy's own `sudo limine-snapper-restore` (interactive, reboots when done, preserves `/home`).
- **Quota helper** — per-snapshot sizes need btrfs quotas; if they're off, the panel offers to enable them.

Boot entries for snapshots appear automatically in the Limine boot menu via `limine-snapper-sync` — no action needed.

## Requirements

- Omarchy 4 (Quickshell "quattro" shell)
- `snapper` + a btrfs root (standard on Omarchy installs)
- `pkexec` (ships with Omarchy's polkit setup) — all privileged work goes through `bin/snapper-helper` via polkit, so you'll get one password prompt; polkit caches it for subsequent polls

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

- `BarWidget.qml` polls `pkexec bin/snapper-helper status` on a timer (gated, cheap) and renders the pill. Clicking toggles `Panel.qml`.
- `bin/snapper-helper` (python3, runs as root via pkexec) is the only privileged piece. It shells out to `snapper` and `btrfs` with fixed argv — never with interpolated shell strings — and prints one JSON document. Snapshot descriptions are rendered as plain text, never as markup.
- Mutations (`create`, `delete`, `cleanup`, `quota-enable`) run through the same helper; each prompts via polkit at click time, which is the expected UX for a destructive action.
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

Test the helper's parsing without snapper by feeding it sample output:

```bash
python3 - <<'EOF'
import importlib.util
spec = importlib.util.spec_from_file_location("sg", "bin/snapper-helper")
sg = importlib.util.module_from_spec(spec); spec.loader.exec_module(sg)
sample = """ # | Type   | Pre # | Date                  | User | Cleanup | Description      | Userdata
---+--------+-------+-----------------------+------+---------+------------------+----------
0  | single |       |                       | root |         | current          |
42 | pre    |       | Mon 2026-09-28 14:00  | root | number  | omarchy update   | important=no
"""
for s in sg.parse_snapper_list(sample, "root"):
    print(s["number"], s["type"], repr(s["description"]), repr(s["userdata"]))
EOF
```

## Notes / limitations

- Snapshots live on the same disk as the system. This is an undo button, not a backup.
- Per-snapshot sizes require btrfs quotas (`btrfs quota enable /`); there's a small ongoing accounting cost, which is why it's opt-in via the panel button.
- `timeline` snapshots aren't created by Omarchy's config (`TIMELINE_CREATE=no`); cleanup covers the `number` class only, matching `omarchy-snapshot`.
- Plugin code is unsandboxed by design in Omarchy — only install plugins from sources you trust, including this one. Review `bin/snapper-helper` if you like; it's short.
