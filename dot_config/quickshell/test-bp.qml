import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    Theme { id: theme }

    Item {
        id: root

        readonly property string aetherBin: "/home/bldnwine/aethergo/build/bin/aether"

        readonly property color bg:   theme.bg
        readonly property color sep:  theme.sep
        readonly property color ink:  theme.ink
        readonly property color inkDeep: theme.inkDeep
        readonly property color seal: theme.seal
        readonly property int cornerRadius: theme.cornerRadius
        readonly property string mono: theme.mono

        property bool aetherVisible: false
        property var  aetherBlueprints: []
        property int  selectedAether: -1
        property bool aetherLoading: false
        property string aetherQuery: ""

        readonly property var aetherFiltered: {
            const q = root.aetherQuery.toLowerCase();
            if (q === "") return root.aetherBlueprints;
            return root.aetherBlueprints.filter(b =>
                String(b.name || "").toLowerCase().indexOf(q) !== -1
            );
        }

        function openAether() {
            root.aetherQuery = "";
            root.selectedAether = 0;
            root.refreshAetherBlueprints();
            root.aetherVisible = true;
        }
        function refreshAetherBlueprints() {
            root.aetherLoading = true;
            aetherProbe.running = false;
            aetherProbe.running = true;
        }
        function moveAetherSelection(delta, wrap) {
            const n = root.aetherFiltered.length;
            if (n === 0) { root.selectedAether = -1; return; }
            const cur = root.selectedAether < 0 ? 0 : root.selectedAether;
            let next = cur + delta;
            if (wrap) {
                next = ((next % n) + n) % n;
            } else {
                if (next < 0) next = 0;
                else if (next >= n) next = n - 1;
            }
            root.selectedAether = next;
        }
        function applyAetherBlueprint(name) {
            if (!name) return;
            root.run(root.aetherBin + " --apply-blueprint " + JSON.stringify(name));
            root.aetherQuery = "";
        }

        Process { id: runner; running: false }
        function run(cmd) {
            runner.command = ["bash", "-lc", cmd];
            runner.running = false;
            runner.running = true;
        }

        Process {
            id: aetherProbe
            running: false
            command: [root.aetherBin, "--list-blueprints", "--json"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let arr = [];
                    try {
                        const obj = JSON.parse(this.text);
                        arr = (obj.blueprints || []).slice();
                    } catch (_) { arr = []; }
                    arr.sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
                    root.aetherBlueprints = arr;
                    root.aetherLoading = false;
                    root.selectedAether = arr.length > 0 ? 0 : -1;
                }
            }
        }

        BlueprintsPopup { root: root }

        Component.onCompleted: root.openAether()
    }
}
