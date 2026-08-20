function promptLooksFingerprint(text) {
    var s = String(text || "").toLowerCase();
    return s.indexOf("finger") !== -1 || s.indexOf("fprint") !== -1 || s.indexOf("swipe") !== -1;
}

function fingerprintFirstFromPamConfig(raw) {
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "");
        if (!line || line.charAt(0) === "#") continue;
        if (!line.match(/^auth\s+/)) continue;
        return line.indexOf("pam_fprintd.so") !== -1;
    }
    return false;
}

function extractCommand(message, actionId) {
    var text = String(message || "").trim();
    if (!text) return "";
    var quotedMatch = text.match(/[`\x27\x22\u2018\u2019\u201c\u201d]([^`\x27\x22\u2018\u2019\u201c\u201d]+)[`\x27\x22\u2018\u2019\u201c\u201d]/);
    if (quotedMatch && quotedMatch[1]) return quotedMatch[1].trim();
    var runMatch = text.match(/to run (?:the program )?([^\s]+(?:\s+[^\s]+)*?) as the super user/i);
    if (runMatch && runMatch[1]) return runMatch[1].trim();
    var runSimple = text.match(/to run (?:the program )?([^\s]+)/i);
    if (runSimple && runSimple[1]) return runSimple[1].trim();
    var actMatch = text.match(/to (?:start|stop|restart|reload|enable|disable) ([^\s]+)/i);
    if (actMatch && actMatch[1]) return actMatch[1].trim();
    return "";
}

if (typeof module !== "undefined") {
    module.exports = {
        promptLooksFingerprint: promptLooksFingerprint,
        fingerprintFirstFromPamConfig: fingerprintFirstFromPamConfig,
        extractCommand: extractCommand
    };
}
