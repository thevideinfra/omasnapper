.pragma library

// Shared formatting helpers for Snapper.

function fmtBytes(bytes) {
    var b = Number(bytes || 0);
    if (b <= 0) return "0 B";
    var units = ["B", "K", "M", "G", "T"];
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
        b /= 1024;
        i++;
    }
    return (i === 0 ? Math.round(b) : b.toFixed(1)) + units[i];
}

function typeLabel(type) {
    // snapper snapshot types: single / pre / post
    if (type === "pre") return "pre";
    if (type === "post") return "post";
    return "single";
}
