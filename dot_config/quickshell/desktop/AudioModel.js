function volumePercent(node) {
    var channels = node && node.volume ? Object.keys(node.volume) : [];
    if (!channels.length) return 0;
    var total = 0;
    for (var i = 0; i < channels.length; i++) {
        var channel = node.volume[channels[i]];
        total += Number(channel.value) / 65536 * 100;
    }
    return Math.round(total / channels.length);
}

function parseSnapshot(raw) {
    var sourceMarker = raw.indexOf("\n__SOURCES__\n");
    var defaultMarker = raw.indexOf("\n__DEFAULTS__\n");
    if (sourceMarker < 0 || defaultMarker < sourceMarker) return null;
    try {
        var sinks = JSON.parse(raw.slice(0, sourceMarker));
        var sources = JSON.parse(raw.slice(sourceMarker + 13, defaultMarker));
        var names = raw.slice(defaultMarker + 14).trim().split("\n");
        var sinkName = names[0] || "";
        var sourceName = names[1] || "";
        var physicalName = names[2] || "";
        if (sinkName === "effect_input.eq" && physicalName) sinkName = physicalName;
        var sink = sinks.find(function(n) { return n.name === sinkName; });
        var source = sources.find(function(n) { return n.name === sourceName; });
        if (!sink) return null; // a daemon restart must not replace good state with zeroes
        var port = String(sink.active_port || "");
        var headphones = /headphone|headset|hp/.test(port);
        var type = /bluez|bluetooth/.test(sinkName) ? (headphones ? "hp" : "bt")
            : /hdmi|dp|displayport/.test(sinkName) ? "hdmi" : headphones ? "hp" : "spk";
        return {
            sinkName: sinkName,
            volume: volumePercent(sink), muted: sink.mute === true,
            inputVolume: volumePercent(source), inputMuted: source ? source.mute === true : false,
            description: sink.description || "", type: type,
            port: headphones ? "Headphones" : /speaker/.test(port) ? "Speakers" : port
        };
    } catch (e) {
        return null;
    }
}

if (typeof module !== "undefined") module.exports = { volumePercent, parseSnapshot };
