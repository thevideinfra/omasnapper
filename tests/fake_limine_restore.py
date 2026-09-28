#!/usr/bin/env python3
"""Stand-in for limine-snapper-restore, run by test_restore.py in a pty.

It prints the same prompts, in the same order, as limine-snapper-sync
--restore when the system is not booted into a snapshot. FAKE_SCENARIO picks
how it behaves; every line it reads is appended to FAKE_INPUT_LOG.
"""

import os
import sys

scenario = os.environ.get("FAKE_SCENARIO", "ok")
log = open(os.environ["FAKE_INPUT_LOG"], "a")
ids = ["6", "7", "8", "9"]


def ask(prompt):
    sys.stdout.write(prompt)
    sys.stdout.flush()
    line = sys.stdin.readline().strip()
    log.write(line + "\n")
    log.flush()
    return line


print("\n ID │ Date                │ Description ")
for i in ids:
    print(" %s  │ 2026-09-18 00:23:37 │ 4.0.4-1     " % i)
while True:
    print("\n Select snapshot to restore (method: replace)\n [↑/↓] select | type [ID] | [c] cancel\n")
    choice = ask("Choice: ")
    if "cancel".startswith(choice.lower()) and choice:
        print("Aborted.")
        sys.exit(0)
    if choice in ids:
        break
    sys.stderr.write("\x1b[31mInvalid snapshot ID: \x1b[0m%s\nPlease try again.\n" % choice)

if scenario == "corrupt":
    print("\n\n Select snapshot action\n [s] Select another snapshot\n [r] Restore anyway\n [c] Cancel\n")
    if ask("Choice [s/r/c]: ").lower().startswith("c"):
        print("Aborted.")
        sys.exit(0)

ask("Description for backup subvolume @: ")

if scenario == "fail":
    print("ERROR: The restore failed.")
    while ask("Close the terminal when ready? [y/N]: ").lower() != "y":
        pass
    sys.exit(1)

print("Success: restored snapshot %s" % choice)
sys.exit(0)
