import QtQuick
import Quickshell
import Quickshell.Io
import "WarpModel.js" as Model

Item {
  id: root
  property string cliPath: "warp-cli"
  // Match the existing NOPASSWD sudoers entries for this exact systemctl argv.
  property var daemonCommandPrefix: ["sudo", "-n", "/usr/bin/systemctl"]
  property int actionTimeoutMs: 30000
  property int daemonTimeoutMs: 120000
  property int startReadinessTimeoutMs: 12000

  // -1 until the first `which warp-cli` answers, then 0/1. Polling stays
  // parked until the CLI exists.
  property int installedProbe: -1
  readonly property bool probed: installedProbe !== -1
  property bool installed: false
  property bool available: false
  property bool daemonDown: false
  property bool needsRegistration: false
  property bool needsTos: false
  property bool connected: false
  property bool connecting: false
  property bool statusKnown: false
  readonly property bool detailsReady: installed && statusKnown && !daemonDown && !needsTos

  // Track a pending request separately from the actual connection state.
  // The icon must not claim the tunnel is connected before the daemon does.
  property int _desired: -1
  readonly property bool active: connected

  property bool refreshing: false
  property string status: "Unknown"
  property string statusText: "Checking…"
  property string reasonText: ""
  readonly property string displayStatusText: daemonTransition && _daemonAction === "start" ? "Starting daemon…"
    : daemonTransition && _daemonAction === "stop" ? "Stopping daemon…"
    : _desired === 0 ? "Disconnecting…" : _desired === 1 ? "Connecting…" : statusText

  property string mode: ""
  property bool alwaysOn: false
  property bool switchLocked: false
  property string splitTunnelText: ""
  property var splitTunnel: ({})
  property bool disableForWifi: false
  property bool disableForEthernet: false
  property string familiesMode: ""

  property bool registered: false
  property string accountLabel: ""
  property string accountType: ""
  property string organization: ""
  property string deviceId: ""
  property string deviceName: ""

  property var tunnelStats: ({})
  property string settingMode: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: 60
  readonly property bool busy: daemonTransition || _actionPending || _daemonPending || whichProcess.running || statusProcess.running || settingsProcess.running ||
    registrationProcess.running || statsProcess.running || actionProcess.running || daemonProcess.running
  readonly property var modeRows: Model.modeRows(mode)
  readonly property bool canToggle: installed && !daemonDown && !needsTos && !busy && _desired === -1
  readonly property bool tunnelMode: Model.isTunnelMode(mode)

  property string _statusOutput: ""
  property string _statusError: ""
  property double _lastRegistrationMs: 0

  property bool _actionTimedOut: false
  property bool _daemonTimedOut: false
  property bool _actionPending: false
  property bool _daemonPending: false

  // Tracks a privileged systemctl start/stop while the unit is settling.
  // Status polls that land mid-transition must not clobber the optimistic
  // daemonDown state (previously: the next `warp-cli status` poll flipped the
  // popup straight back before systemctl finished).
  property bool daemonTransition: false
  property string _daemonAction: ""
  property int _daemonEpoch: 0
  property bool _daemonStartPending: false
  property int _startGoodPolls: 0
  property double _startGraceUntil: 0
  property int _downConfirm: 0

  // Paused while the bar is hidden to stop background forks. Bound from
  // Navbar as `!barHidden || warpVisible` so the popup stays live.
  // Direct refresh() calls (popup open, IPC, post-action) still run.
  property bool pollingEnabled: true

  function modeLabel(value) {
    return Model.modeLabel(value)
  }

  function modeDescription(value) {
    return Model.modeDescription(value)
  }

  function copyToClipboard(value) { copyText(value, "Copied to clipboard") }

  function copyText(value, message) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", text])
    flash(message || "Copied")
  }

  function copyDeviceId() {
    if (deviceId === "") return
    copyToClipboard(deviceId)
  }

  function flash(message) {
    actionStatus = Model.elide(message)
    actionStatusTimer.restart()
  }

  function refresh() {
    if (!installed) {
      if (whichProcess.running) return
      refreshing = true
      whichProcess.command = ["which", root.cliPath]
      whichProcess.running = true
      return
    }
    refreshStatus()
  }

  function refreshStatus() {
    if (daemonTransition && !_daemonStartPending) return
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.pollEpoch = root._daemonEpoch
    statusProcess.command = warpCommand(["status"])
    statusProcess.running = true
  }

  // Everything except `status` only makes sense once the daemon answers, so the
  // follow-up queries are chained off a successful status read.
  function refreshDetails() {
    if (!settingsProcess.running) {
      settingsProcess.command = warpCommand(["settings"])
      settingsProcess.running = true
    }
    var now = Date.now()
    if (!registrationProcess.running && (_lastRegistrationMs === 0 || now - _lastRegistrationMs > 300000)) {
      _lastRegistrationMs = now
      registrationProcess.command = warpCommand(["registration", "show"])
      registrationProcess.running = true
    }
    if (connected && !statsProcess.running) {
      statsProcess.command = warpCommand(["tunnel", "stats"])
      statsProcess.running = true
    } else if (!connected) {
      tunnelStats = ({})
    }
  }

  // --accept-tos keeps calls machine readable and non-blocking
  function warpCommand(args) {
    var command = [root.cliPath, "--accept-tos", "--json", "--no-paginate", "--no-ansi"]
    for (var i = 0; i < args.length; i++) command.push(args[i])
    return command
  }

  function resetUnavailable(message) {
    available = false
    connected = false
    connecting = false
    statusKnown = false
    _desired = -1
    status = "Unavailable"
    statusText = message
    reasonText = ""
    tunnelStats = ({})
  }

  function applyStatus(raw, exitCode, stderr, epoch) {
    // A status request issued before the daemon command must not settle it.
    if (epoch !== undefined && epoch !== root._daemonEpoch) return
    if (daemonTransition && !_daemonStartPending) return
    var parsed = Model.parseStatus(raw, exitCode, stderr)
    if (root._daemonStartPending) {
      if (!parsed.ok || parsed.daemonDown) {
        root._startGoodPolls = 0
        return
      }
      root._startGoodPolls += 1
      if (root._startGoodPolls < 2) return
      root._daemonStartPending = false
      root.daemonTransition = false
      root._daemonAction = ""
      root._startGraceUntil = Date.now() + 5000
      root._downConfirm = 0
      root.actionStatus = ""
      actionStatusTimer.stop()
    }

    // A malformed or failed poll should not overwrite the last known state.
    if (!parsed.ok) {
      root._downConfirm = 0
      lastError = parsed.error || "Could not read warp-cli status"
      return
    }
    if (parsed.daemonDown && Date.now() < root._startGraceUntil) {
      root._downConfirm += 1
      if (root._downConfirm < 2) {
        graceConfirmTimer.restart()
        return
      }
    }
    root._downConfirm = 0
    graceConfirmTimer.stop()
    if (parsed.daemonDown) root._startGraceUntil = 0
    daemonDown = parsed.daemonDown === true
    needsTos = parsed.needsTos === true
    needsRegistration = parsed.needsRegistration === true
    available = parsed.available === true
    status = parsed.status
    statusText = parsed.statusText
    reasonText = parsed.reasonText || ""
    statusKnown = true

    connected = parsed.connected === true
    connecting = parsed.connecting === true
    if (_desired !== -1 && (connected === (_desired === 1) || needsRegistration
        || !/^(connected|connecting|disconnected)$/i.test(status))) _desired = -1
    if (_desired === 1) connecting = true
    lastError = ""
    if (/^(unable|error|unknown)$/i.test(status)) lastError = reasonText || statusText
    if (daemonDown || needsTos) {
      clearDaemonDetails()
      return
    }

    refreshDetails()
  }

  readonly property var splitTunnelEntries: splitTunnel && splitTunnel.entries ? splitTunnel.entries : []
  readonly property string splitTunnelSummary: splitTunnel && splitTunnel.summary ? splitTunnel.summary : ""

  function applySettings(raw) {
    var parsed = Model.parseSettings(raw)
    if (parsed.ok !== true) return
    splitTunnel = Model.parseSplitTunnel(raw)
    mode = parsed.mode
    alwaysOn = parsed.alwaysOn
    switchLocked = parsed.switchLocked
    splitTunnelText = Model.splitTunnelText(parsed)
    disableForWifi = parsed.disableForWifi
    disableForEthernet = parsed.disableForEthernet
    familiesMode = parsed.familiesMode
  }

  function applyRegistration(raw) {
    var parsed = Model.parseRegistration(raw)
    if (!parsed.ok) {
      lastError = parsed.error || "Could not read WARP registration"
      return
    }
    registered = parsed.registered === true
    accountType = parsed.accountType
    accountLabel = parsed.accountLabel
    organization = parsed.organization
    deviceId = parsed.deviceId
    deviceName = parsed.deviceName
    if (!registered) needsRegistration = true
    else needsRegistration = false
  }

  function toggleConnection() {
    if (!canToggle) return
    if (active) disconnect()
    else connect()
  }

  function connect() {
    if (!canToggle) return
    if (!registered) {
      if (!needsRegistration) {
        _lastRegistrationMs = 0
        refresh()
        flash("Checking device registration…")
        return
      }
      register()
      return
    }
    _desired = 1
    connecting = true
    statusText = "Connecting…"
    runAction(["connect"], "Connecting…")
  }

  function disconnect() {
    if (!canToggle) return
    _desired = 0
    statusText = "Disconnecting…"
    runAction(["disconnect"], "Disconnecting…")
  }

  function register() {
    if (!installed || daemonDown || _actionPending || actionProcess.running) return
    _desired = -1
    runAction(["registration", "new"], "Registering device…")
  }

  function setMode(value) {
    var next = String(value || "")
    if (!installed || daemonDown || next === "" || _actionPending || actionProcess.running) return
    if (switchLocked) {
      lastError = "Mode is locked by policy"
      flash(lastError)
      return
    }
    if (next === mode) return
    settingMode = next
    runAction(["mode", next], "Switching to " + Model.modeLabel(next) + "…")
  }

  function setFamiliesMode(value) {
    var next = String(value || "")
    if (!installed || daemonDown || next === "" || _actionPending || actionProcess.running) return
    runAction(["dns", "families", next], "DNS filtering: " + next)
  }

  function clearDaemonDetails() {
    connected = false
    connecting = false
    _desired = -1
    registered = false
    mode = ""
    accountLabel = ""
    accountType = ""
    organization = ""
    deviceId = ""
    deviceName = ""
    alwaysOn = false
    switchLocked = false
    splitTunnel = ({})
    splitTunnelText = ""
    tunnelStats = ({})
  }

  function startDaemon() { manageDaemon("start") }
  function stopDaemon() { manageDaemon("stop") }
  function manageDaemon(action) {
    if (daemonTransition || _daemonPending || daemonProcess.running || _actionPending || actionProcess.running) return
    lastError = ""
    _daemonEpoch += 1
    if (statusProcess.running) statusProcess.running = false
    _daemonTimedOut = false
    _daemonPending = true
    _daemonStartPending = false
    _startGoodPolls = 0
    _startGraceUntil = 0
    _downConfirm = 0
    graceConfirmTimer.stop()
    _daemonAction = action
    daemonTransition = true
    actionStatus = action === "start" ? "Starting WARP daemon…" : "Stopping WARP daemon…"
    if (action === "start") {
      daemonDown = true
      statusKnown = true
    } else {
      daemonDown = true
      clearDaemonDetails()
      status = "DaemonDown"
      statusText = "WARP daemon is not running"
      reasonText = ""
    }
    daemonProcess.command = root.daemonCommandPrefix.concat([action, "warp-svc"])
    daemonProcess.running = true
  }

  function runAction(args, label) {
    if (_actionPending || actionProcess.running) return
    _actionTimedOut = false
    _actionPending = true
    actionStatus = label || ""
    actionProcess.command = warpCommand(args)
    actionProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: (root.installed || !root.probed) && root.pollingEnabled
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: (root.installed || !root.probed) && root.pollingEnabled
    onTriggered: {
      ticks += 1
      if (root.available || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    running: statusProcess.running || settingsProcess.running || registrationProcess.running || statsProcess.running
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (settingsProcess.running) settingsProcess.running = false
      if (registrationProcess.running) registrationProcess.running = false
      if (statsProcess.running) statsProcess.running = false
      root.refreshing = false
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: root._daemonStartPending
    onTriggered: root.refreshStatus()
  }
  Timer {
    interval: root.startReadinessTimeoutMs
    running: root._daemonStartPending
    onTriggered: {
      root._daemonStartPending = false
      root.daemonTransition = false
      root._daemonAction = ""
      root.lastError = "WARP daemon started but did not become ready"
      root.flash(root.lastError)
      delayedRefresh.restart()
    }
  }
  Timer {
    id: graceConfirmTimer
    interval: 500
    onTriggered: root.refreshStatus()
  }

  Timer {
    interval: 15000
    running: root._desired !== -1
    onTriggered: {
      const wanted = root._desired
      root._desired = -1
      root.connecting = false
      if (/^(connecting|disconnecting)/i.test(root.statusText)) root.statusText = "Checking status…"
      root.lastError = wanted === 1 ? "WARP did not finish connecting; refresh to confirm its state"
        : "WARP did not finish disconnecting; refresh to confirm its state"
      root.flash(root.lastError)
      root.refresh()
    }
  }
  Timer {
    interval: root.actionTimeoutMs
    running: actionProcess.running
    onTriggered: { root._actionTimedOut = true; actionProcess.running = false }
  }
  Timer {
    interval: root.daemonTimeoutMs
    running: daemonProcess.running
    onTriggered: { root._daemonTimedOut = true; daemonProcess.running = false }
  }

  Timer {
    id: delayedRefresh
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: settleRefresh
    interval: 2500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.installedProbe = root.installed ? 1 : 0
      if (root.installed) root.refreshStatus()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    property int pollEpoch: 0
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      if (pollEpoch !== root._daemonEpoch) {
        if (root._daemonStartPending) Qt.callLater(root.refreshStatus)
        return
      }
      root.applyStatus(String(statusStdout.text || root._statusOutput || ""), exitCode,
        String(statusStderr.text || root._statusError || ""), pollEpoch)
    }
  }

  Process {
    id: settingsProcess
    running: false
    command: []
    stdout: StdioCollector { id: settingsStdout; waitForEnd: true }
    stderr: StdioCollector { id: settingsStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applySettings(String(settingsStdout.text || ""))
    }
  }

  Process {
    id: registrationProcess
    running: false
    command: []
    stdout: StdioCollector { id: registrationStdout; waitForEnd: true }
    stderr: StdioCollector { id: registrationStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var raw = String(registrationStdout.text || "")
      if (exitCode === 0 || /registrationmissing/i.test(Model.errorCode(raw))) root.applyRegistration(raw)
      else root.lastError = Model.errorMessage(raw || String(registrationStderr.text || "")) || "Could not read WARP registration"
    }
  }

  Process {
    id: statsProcess
    running: false
    command: []
    stdout: StdioCollector { id: statsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.tunnelStats = exitCode === 0 ? Model.parseTunnelStats(String(statsStdout.text || "")) : ({})
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || "")
      root._actionPending = false
      var stderr = String(actionStderr.text || "")
      var failed = root._actionTimedOut || exitCode !== 0 || Model.errorCode(stdout) !== ""
      if (failed) {
        root._desired = -1
        root.connecting = false
        if (/^(connecting|disconnecting)/i.test(root.statusText)) root.statusText = "Checking status…"
        root.lastError = root._actionTimedOut ? "WARP action timed out; refresh to confirm its outcome" : Model.errorMessage(stdout || stderr) || "warp-cli command failed"
        root.flash(root.lastError)
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastRegistrationMs = 0
      }
      root.settingMode = ""
      delayedRefresh.restart()
      settleRefresh.restart()
    }
  }

  Process {
    id: daemonProcess
    running: false
    command: []
    stdout: StdioCollector { id: daemonStdout; waitForEnd: true }
    stderr: StdioCollector { id: daemonStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var action = root._daemonAction
      root._daemonPending = false
      if (exitCode !== 0 || root._daemonTimedOut) {
        root._daemonStartPending = false
        root._daemonAction = ""
        root.daemonTransition = false
        // A failed command may leave the actual daemon state uncertain.
        root.lastError = root._daemonTimedOut ? "WARP daemon command timed out; refresh to confirm its state" : Model.elide(String(daemonStderr.text || daemonStdout.text || "Could not manage warp-svc"))
        if (root.lastError === "") root.lastError = "Could not manage warp-svc"
        root.flash(root.lastError)
      } else if (action === "stop") {
        root._daemonAction = ""
        root.daemonTransition = false
        root.lastError = ""
        root.daemonDown = true
        root.statusKnown = true
        root.status = "DaemonDown"
        root.statusText = "WARP daemon is not running"
        root.reasonText = ""
        root.clearDaemonDetails()
        root.flash("WARP daemon stopped")
      } else {
        // systemctl can return before warp-cli can reach the daemon.
        root._daemonStartPending = true
        root._startGoodPolls = 0
        Qt.callLater(root.refreshStatus)
      }
      delayedRefresh.restart()
      settleRefresh.restart()
    }
  }
}
