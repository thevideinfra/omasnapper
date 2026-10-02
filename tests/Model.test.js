// Run with: node --test tests/*.test.js
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

test("fmtBytes uses binary units with one decimal", () => {
  assert.equal(M.fmtBytes(0), "0 B")
  assert.equal(M.fmtBytes(512), "512 B")
  assert.equal(M.fmtBytes(1536), "1.5 KB")
  assert.equal(M.fmtBytes(805000000000), "749.7 GB")
})

test("statusLine counts snapshots and free space in caps", () => {
  assert.equal(M.statusLine(4, 805000000000), "4 SNAPSHOTS · 749.7 GB FREE")
  assert.equal(M.statusLine(1, 0), "1 SNAPSHOT")
  assert.equal(M.statusLine(0, 0), "NO SNAPSHOTS YET")
})

test("shortDate drops the year and seconds", () => {
  assert.equal(M.shortDate("2026-09-25 22:44:02"), "Sep 25, 22:44")
  assert.equal(M.shortDate(""), "")
})

test("originIcon picks a glyph per origin", () => {
  assert.equal(M.originIcon("omarchy-update"), "󰚰")
  assert.equal(M.originIcon("manual"), "󰄄")
  assert.equal(M.originIcon("restore-backup"), "󰁯")
  assert.equal(M.originIcon("other"), "󰋊")
})

test("density and font scales match dotsync", () => {
  assert.equal(M.densityScale("compact"), 0.61)
  assert.equal(M.densityScale("normal"), 0.71)
  assert.equal(M.fontSizeScale("large"), 1.07)
})

test("helperError explains a dismissed password prompt", () => {
  assert.equal(M.helperError("", 126), "Password prompt was dismissed.")
  assert.equal(M.helperError('{"ok": false, "error": "boom"}', 1), "boom")
  assert.equal(M.helperError("garbage", 1), "omasnapper-helper failed (exit 1).")
})

test("shortDate follows a 12-hour bar clock", () => {
  assert.equal(M.shortDate("2026-09-25 22:44:02", "ddd d MMM h:mm AP"), "Sep 25, 10:44 PM")
  assert.equal(M.shortDate("2026-09-18 00:23:37", "h:mm ap"), "Sep 18, 12:23 am")
  assert.equal(M.shortDate("2026-09-18 12:05:00", "hh:mm AP"), "Sep 18, 12:05 PM")
})

test("shortDate stays 24-hour for a 24-hour or missing bar clock", () => {
  assert.equal(M.shortDate("2026-09-25 22:44:02", "dddd HH:mm"), "Sep 25, 22:44")
  assert.equal(M.shortDate("2026-09-25 09:04:02", ""), "Sep 25, 09:04")
})

test("clockFormat finds the omarchy.clock entry in any bar section", () => {
  const layout = { left: [], center: [{ id: "omarchy.menu" }, { id: "omarchy.clock", format: "ddd d MMM h:mm AP" }], right: [] }
  assert.equal(M.clockFormat(layout), "ddd d MMM h:mm AP")
  assert.equal(M.clockFormat({ left: [{ id: "omarchy.clock" }] }), "dddd HH:mm")
  assert.equal(M.clockFormat({}), "")
  assert.equal(M.clockFormat(null), "")
})

test("changeLine shows one package change without pkgrel", () => {
  assert.equal(M.changeLine({ action: "upgraded", package: "mesa", from: "26.1.0-1", to: "26.1.1-2" }), "mesa 26.1.0 → 26.1.1")
  assert.equal(M.changeLine({ action: "installed", package: "foo", from: "", to: "1.0-1" }), "+ foo 1.0")
  assert.equal(M.changeLine({ action: "removed", package: "bar", from: "2.0-1", to: "" }), "− bar 2.0")
})

test("originIcon has a clock for scheduled snapshots", () => {
  assert.equal(M.originIcon("scheduled"), "󰃰")
})

const snaps = [
  { number: 9, cleanup: "number" }, { number: 8, cleanup: "number" },
  { number: 7, cleanup: "" }, { number: 6, cleanup: "number" },
  { number: 5, cleanup: "timeline" }, { number: 4, cleanup: "number" }
]

test("wouldDelete lists auto-deleted snapshots past the keep count, oldest last", () => {
  assert.deepEqual(M.wouldDelete(snaps, 2, true), [6, 4])
  assert.deepEqual(M.wouldDelete(snaps, 4, true), [])
})

test("wouldDelete spares pinned and scheduled snapshots", () => {
  assert.deepEqual(M.wouldDelete(snaps, 1, true), [8, 6, 4])
})

test("wouldDelete is empty when auto-delete is off", () => {
  assert.deepEqual(M.wouldDelete(snaps, 1, false), [])
})

test("fileLine marks added, removed and changed files", () => {
  assert.equal(M.fileLine({ change: "added", path: "/a" }), "+ /a")
  assert.equal(M.fileLine({ change: "removed", path: "/b" }), "− /b")
  assert.equal(M.fileLine({ change: "changed", path: "/c" }), "~ /c")
})

test("settingBool accepts booleans and strings", () => {
  assert.equal(M.settingBool("false", true), false)
  assert.equal(M.settingBool(true, false), true)
  assert.equal(M.settingBool(undefined, true), true)
})

test("snapshotName trims the typed name and falls back when blank", () => {
  assert.equal(M.snapshotName("  before kernel swap "), "before kernel swap")
  assert.equal(M.snapshotName("   "), "Manual snapshot")
  assert.equal(M.snapshotName(undefined), "Manual snapshot")
})

test("densityScale reads roomy, and comfortable from older settings", () => {
  assert.equal(M.densityScale("roomy"), 0.83)
  assert.equal(M.densityScale("comfortable"), 0.83)
})

test("parsePalette reads quoted six-digit hex colours from colors.toml", () => {
  const toml = 'accent = "#59C98D"\nred = "#E0607F"\n# comment\nbackground = "#101315"\nbad = "not-a-colour"\nshort = "#abc"\n'
  assert.deepEqual(M.parsePalette(toml), { accent: "#59C98D", red: "#E0607F", background: "#101315" })
  assert.deepEqual(M.parsePalette(undefined), {})
})

test("accentChoices lists theme first, then palette colours in a fixed order", () => {
  const palette = { green: "#4FA86F", blue: "#6E7FB8", accent: "#59C98D", red: "#E0607F" }
  assert.deepEqual(M.accentChoices(palette), ["theme", "blue", "green", "red"])
  assert.deepEqual(M.accentChoices({}), ["theme"])
})

test("accentColor returns the palette colour, or null for theme and unknown names", () => {
  const palette = { blue: "#6E7FB8" }
  assert.equal(M.accentColor("blue", palette), "#6E7FB8")
  assert.equal(M.accentColor("theme", palette), null)
  assert.equal(M.accentColor("orange", palette), null)
  assert.equal(M.accentColor(undefined, palette), null)
})

test("manifestVersion reads the version, or empty when unreadable", () => {
  assert.equal(M.manifestVersion('{"version": "0.2.0"}'), "0.2.0")
  assert.equal(M.manifestVersion("nope"), "")
})
