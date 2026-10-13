function recentHashes(hashes, now) {
    var next = {};
    Object.keys(hashes).forEach(function(key) {
        if (now - hashes[key] < 3000) next[key] = hashes[key];
    });
    return next;
}

function outsideRetention(timestamp, now, keepDays) {
    return timestamp < now - Math.max(0, keepDays) * 86400000;
}

if (typeof module !== "undefined") module.exports = { recentHashes, outsideRetention };
