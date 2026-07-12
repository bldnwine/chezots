.pragma library

function parse(text) {
	var result = {};
	var lines = text.split("\n");
	for (var i = 0; i < lines.length; i++) {
		var m = lines[i].match(/^\s*(\w+)\s*=\s*"#([0-9a-fA-F]{6})"/);
		if (m) result[m[1]] = "#" + m[2];
	}
	return result;
}

function apply(theme, palette) {
	if (palette.background) theme.paper = palette.background;
	if (palette.foreground) theme.ink = palette.foreground;
	if (palette.accent) theme.seal = palette.accent;
}
