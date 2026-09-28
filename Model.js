// Helpers for the videinfra.snapper panel. Pure functions, testable via node.

function fmtBytes(bytes) {
  var b = Number(bytes || 0)
  if (b <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024
    i++
  }
  return (i === 0 ? Math.round(b) : b.toFixed(1)) + " " + units[i]
}

// The caps line under the panel title: snapshot count, then free space.
function statusLine(count, freeBytes) {
  if (count === 0) return "NO SNAPSHOTS YET"
  var line = count === 1 ? "1 snapshot" : count + " snapshots"
  if (freeBytes > 0) line += " · " + fmtBytes(freeBytes) + " free"
  return line.toUpperCase()
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "2026-09-25 22:44:02" (snapper's local time) to "Sep 25, 22:44".
function shortDate(date) {
  var m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/.exec(String(date || ""))
  if (!m) return String(date || "")
  return MONTHS[Number(m[2]) - 1] + " " + Number(m[3]) + ", " + m[4] + ":" + m[5]
}

// Row glyph for who made the snapshot (bin/snapper-helper's `origin`).
function originIcon(origin) {
  if (origin === "omarchy-update") return "󰚰"   // nf-md-update
  if (origin === "manual") return "󰄄"           // nf-md-camera
  if (origin === "restore-backup") return "󰁯"   // nf-md-backup_restore
  return "󰋊"                                     // nf-md-harddisk
}

// Spacing multiplier for the density chosen in settings. Same scales as
// omaudiopanel, tandem and dotsync, so the panels match side by side.
function densityScale(name) {
  if (name === "compact") return 0.61
  if (name === "comfortable") return 0.83
  return 0.71
}

// Text size multiplier chosen in settings, applied on top of the density's.
function fontSizeScale(name) {
  if (name === "small") return 0.85
  if (name === "large") return 1.07
  return 0.95
}

// Error text for a failed helper run. pkexec exits 126 when the password
// prompt is dismissed and prints nothing on stdout.
function helperError(stdout, code) {
  if (code === 126) return "Password prompt was dismissed."
  try {
    var doc = JSON.parse(String(stdout || ""))
    if (doc && doc.error) return String(doc.error)
  } catch (e) {}
  return "snapper-helper failed (exit " + code + ")."
}

if (typeof module !== "undefined") {
  module.exports = {
    fmtBytes: fmtBytes,
    statusLine: statusLine,
    shortDate: shortDate,
    originIcon: originIcon,
    densityScale: densityScale,
    fontSizeScale: fontSizeScale,
    helperError: helperError
  }
}
