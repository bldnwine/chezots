"""Run the real Aether CLI with private config; never touch the desktop theme."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

binary = Path(os.environ.get("AETHER_BINARY", str(Path.home() / "aethergo/build/bin/aether")))
with tempfile.TemporaryDirectory(prefix="aether palette integration ") as directory:
    home = Path(directory)
    config = home / ".config"
    theme = config / "aether/theme"
    theme.mkdir(parents=True)
    names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
             "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue",
             "bright_magenta", "bright_cyan", "bright_white"]
    palette = ["#111111", "#aa3344", "#44aa55", "#cccc33", "#4466cc", "#aa44aa", "#44aaaa", "#eeeeee",
               "#777777", "#cc3344", "#55cc66", "#eeee44", "#5577dd", "#cc55cc", "#55cccc", "#ffffff"]
    toml = 'background = "#111111"\nforeground = "#eeeeee"\naccent = "#4466cc"\n'
    toml += "".join(f'{name} = "{value}"\ncolor{i} = "{value}"\n' for i, (name, value) in enumerate(zip(names, palette)))
    (theme / "colors.toml").write_text(toml)
    (theme / "kitty.conf").write_text("unrelated application palette\n")
    wallpaper = home / "wallpaper.jpg"
    wallpaper.write_bytes(b"wallpaper metadata fixture")
    link = config / "omarchy/current/background"
    link.parent.mkdir(parents=True)
    link.symlink_to(wallpaper)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(home / ".local/state"))

    def call(action, payload=None, success=True):
        result = subprocess.run([str(binary), "--quickshell-" + action, "--json"],
                                input=json.dumps(payload) if payload is not None else None,
                                env=env, capture_output=True, text=True, timeout=10)
        doc = json.loads(result.stdout)
        assert doc["ok"] == success, (action, result.stdout, result.stderr)
        assert (result.returncode == 0) == success
        return doc

    first = call("palette")
    assert first["source"]["kind"] == "scratch"
    output = theme / "quickshell.json"
    record = config / "aether/applied-theme.json"
    before = (output.read_bytes(), record.read_bytes())
    overrides = {"qs_paper": "#123456", "qs_ink_deep": "#abcdef", "qs_row_sel": "#10203040"}
    preview = call("preview", {"revision": first["revision"], "overrides": overrides})
    assert (output.read_bytes(), record.read_bytes()) == before
    assert preview["revision"] == first["revision"]
    assert preview["colors"]["bg"] == "#123456f0"
    applied = call("apply", {"revision": first["revision"], "overrides": overrides})
    assert applied["colors"] == preview["colors"]
    assert json.loads(output.read_text())["colors"] == applied["colors"]
    copy = call("save-as", {"revision": applied["revision"], "overrides": overrides, "name": "QS copy"})
    source = config / "aether/blueprints" / copy["source"]["filename"]
    blueprint = json.loads(source.read_text())
    assert blueprint["palette"]["colors"] == palette
    assert blueprint["palette"]["wallpaper"] == str(wallpaper)
    assert blueprint["settings"]["includeGtk"] and blueprint["settings"]["includeQt"]
    assert blueprint["appOverrides"]["quickshell"] == overrides
    saved = call("save", {"revision": copy["revision"], "overrides": {"qs_sep": "#10203044"}})
    assert json.loads(source.read_text())["appOverrides"]["quickshell"] == {"qs_sep": "#10203044"}
    before = (output.read_bytes(), record.read_bytes(), source.read_bytes())
    call("apply", {"revision": first["revision"], "overrides": {}}, success=False)
    call("save-as", {"revision": saved["revision"], "overrides": {}, "name": "QS copy"}, success=False)
    assert (output.read_bytes(), record.read_bytes(), source.read_bytes()) == before
    external = source.read_bytes() + b"\n"
    source.write_bytes(external)
    call("save", {"revision": saved["revision"], "overrides": {}}, success=False)
    assert source.read_bytes() == external
    assert (theme / "colors.toml").read_text() == toml
    assert (theme / "kitty.conf").read_text() == "unrelated application palette\n"
print("Aether palette CLI integration passed")
