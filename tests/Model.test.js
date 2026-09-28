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
  assert.equal(M.helperError("garbage", 1), "snapper-helper failed (exit 1).")
})
