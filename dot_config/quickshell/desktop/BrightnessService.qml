import QtQuick
import Quickshell.Io

// One persistent owner for every local-backlight read and write.
Item {
    id: service
    visible: false
    property string helperPath: Qt.resolvedUrl("scripts/brightness_helper.py").toString().replace(/^file:\/\//, "")
    property var helperCommand: ["python3", helperPath]
    property int timeoutMs: 7000
    property string output: ""
    property var stateByOutput: ({})
    property var rememberedByOutput: ({})
    property string lastError: ""
    property var pending: []
    property var current: null
    property bool timedOut: false
    property bool started: false
    property var generations: ({})
    readonly property bool busy: current !== null || pending.length > 0
    signal brightnessChanged(string output, real percentage)
    signal brightnessRemembered(string output, real previousPercentage)
    signal actionFailed(string output, string message)

    function enqueue(kind, outputName, amount) {
        if (!outputName || (kind !== "refresh" && !isFinite(amount))) return false;
        const jobs = pending.slice();
        const last = jobs.length ? jobs[jobs.length - 1] : null;
        if (kind === "step" && last && last.kind === "step" && last.output === outputName
                && Number.isInteger(amount) && Number.isInteger(last.amount)
                && amount * last.amount > 0) {
            jobs[jobs.length - 1] = Object.assign({}, last, {amount: last.amount + amount});
            pending = jobs;
            return true;
        }
        // Absolute settings may replace each other only within the current
        // run of absolute settings; reads and relative steps are barriers.
        if (kind === "set") {
            for (let i = jobs.length - 1; i >= 0 && jobs[i].kind === "set"; --i) {
                if (jobs[i].output === outputName) { jobs.splice(i, 1); break; }
            }
        }
        jobs.push({kind: kind, output: String(outputName), amount: amount,
                   generation: generations[outputName] || 0});
        pending = jobs;
        pump();
        return true;
    }
    function setBrightness(outputName, percentage) { return enqueue("set", outputName, Number(percentage)); }
    function restoreRemembered(outputName) { return enqueue("restore", outputName, 0); }
    function rememberAndSet(outputName, percentage) { return enqueue("dim", outputName, Number(percentage)); }
    function stepBrightness(outputName, delta) { return enqueue("step", outputName, Number(delta)); }
    function refresh(outputName) { return enqueue("refresh", outputName, 0); }
    // In-flight writes may already have reached the driver. Invalidate their
    // result and discard queued work when a connector disappears.
    function cancelOutput(outputName) {
        const nextGenerations = Object.assign({}, generations);
        nextGenerations[outputName] = (nextGenerations[outputName] || 0) + 1;
        generations = nextGenerations;
        pending = pending.filter(job => job.output !== outputName);
        const states = Object.assign({}, stateByOutput);
        delete states[outputName];
        stateByOutput = states;
    }
    function pump() {
        if (current || worker.running || !pending.length) return;
        const jobs = pending.slice();
        current = jobs.shift();
        pending = jobs;
        output = current.output;
        started = false;
        timedOut = false;
        if (current.kind === "restore" && rememberedByOutput[current.output] === undefined) {
            current = null;
            next.start();
            return;
        }
        const kind = current.kind === "restore" ? "set" : current.kind;
        const amount = current.kind === "restore" ? rememberedByOutput[current.output] : current.amount;
        worker.command = helperCommand.concat([kind, current.output, String(amount)]);
        worker.running = true;
        deadline.restart();
        startGuard.restart();
    }
    function finish(code) {
        if (!current) return;
        deadline.stop(); startGuard.stop();
        killGuard.stop();
        const job = current;
        if (job.generation !== (generations[job.output] || 0)) {
            current = null;
            next.start();
            return;
        }
        let result = null;
        if (!timedOut) {
            try { result = JSON.parse(stdout.text); } catch (e) {}
        }
        const success = code === 0 && result && result.ok === true && result.output === job.output
            && typeof result.percentage === "number" && isFinite(result.percentage)
            && result.percentage >= 0 && result.percentage <= 100
            && (job.kind !== "dim" || (typeof result.previousPercentage === "number"
                && isFinite(result.previousPercentage) && result.previousPercentage >= 0
                && result.previousPercentage <= 100));
        if (success) {
            const states = Object.assign({}, stateByOutput);
            states[job.output] = result.percentage;
            stateByOutput = states;
            lastError = "";
            if (job.kind === "dim") {
                const remembered = Object.assign({}, rememberedByOutput);
                remembered[job.output] = result.previousPercentage;
                rememberedByOutput = remembered;
                brightnessRemembered(job.output, result.previousPercentage);
            }
            brightnessChanged(job.output, result.percentage);
        } else {
            lastError = timedOut ? "Brightness operation timed out" :
                (result && result.error ? String(result.error) : "Brightness operation failed");
            actionFailed(job.output, lastError);
        }
        current = null;
        next.start();
    }
    Process {
        id: worker
        stdout: StdioCollector { id: stdout }
        onStarted: { service.started = true; startGuard.stop(); }
        onExited: function(code) { service.finish(code); }
    }
    Timer { id: deadline; interval: service.timeoutMs; onTriggered: {
        if (!service.current) return;
        service.timedOut = true;
        if (worker.running) { worker.signal(15); killGuard.restart(); }
        else service.finish(-1);
    } }
    Timer { id: killGuard; interval: 1000; onTriggered: if (worker.running) worker.signal(9) }
    Timer { id: startGuard; interval: 1000; onTriggered: {
        if (service.current && !service.started && !worker.running) service.finish(-1);
    } }
    Timer { id: next; interval: 0; onTriggered: service.pump() }
}
