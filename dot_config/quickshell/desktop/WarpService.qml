import QtQuick
import Quickshell
import Quickshell.Io
import "WarpModel.js" as Model

Item {
  id: root

  property var settings: ({})

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

  // Optimistic state so the icon flips the instant you click instead of waiting
  // for the next poll. _desired is -1 while we follow reality, 0/1 while a
  // connect/disconnect is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? connected : (_desired === 1)

  property bool refreshing: false
  property string status: "Unknown"
  property string statusText: "Checking…"
  property string reasonText: ""

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

  readonly property int refreshIntervalSec: 20
  readonly property bool busy: whichProcess.running || statusProcess.running || settingsProcess.running ||
    registrationProcess.running || statsProcess.running || actionProcess.running || daemonProcess.running
  readonly property var modeRows: Model.modeRows(mode)
  readonly property bool canToggle: installed && !daemonDown && !needsTos && !busy
  readonly property bool tunnelMode: Model.isTunnelMode(mode)

  property string _statusOutput: ""
  property string _statusError: ""
  property double _lastRegistrationMs: 0

  function modeLabel(value) {
    return Model.modeLabel(value)
  }

  function modeDescription(value) {
    return Model.modeDescription(value)
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + JSON.stringify(text) + " | wl-copy"])
    flash("Copied to clipboard")
  }

  function copyText(value, message) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + JSON.stringify(text) + " | wl-copy"])
    flash(message && message !== "" ? message : "Copied")
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
      whichProcess.command = ["which", "warp-cli"]
      whichProcess.running = true
      return
    }
    refreshStatus()
  }

  function refreshStatus() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
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
    if (!registrationProcess.running && (!registered || now - _lastRegistrationMs > 300000)) {
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
    var command = ["warp-cli", "--accept-tos", "--json", "--no-paginate", "--no-ansi"]
    for (var i = 0; i < args.length; i++) command.push(args[i])
    return command
  }

  function resetUnavailable(message) {
    available = false
    connected = false
    connecting = false
    _desired = -1
    status = "Unavailable"
    statusText = message
    reasonText = ""
    tunnelStats = ({})
  }

  function applyStatus(raw, exitCode, stderr) {
    var parsed = Model.parseStatus(raw, exitCode, stderr)
    daemonDown = parsed.daemonDown === true
    needsTos = parsed.needsTos === true
    needsRegistration = parsed.needsRegistration === true
    available = parsed.available === true
    status = parsed.status
    statusText = parsed.statusText
    reasonText = parsed.reasonText || ""

    if (!parsed.ok) {
      lastError = parsed.error || "Could not read warp-cli status"
      connected = false
      connecting = false
      _desired = -1
      return
    }

    connected = parsed.connected === true
    connecting = parsed.connecting === true
    if (_desired !== -1 && connected === (_desired === 1)) _desired = -1
    if (daemonDown || needsTos) {
      registered = false
      mode = ""
      accountLabel = ""
      tunnelStats = ({})
      splitTunnel = ({})
      return
    }

    if (connecting && /connectivity/i.test(reasonText)) {
      Quickshell.execDetached(warpCommand(["debug", "connectivity-check", "disable"]))
      delayedRefresh.restart()
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
    registered = parsed.registered === true
    accountType = parsed.accountType
    accountLabel = parsed.accountLabel
    organization = parsed.organization
    deviceId = parsed.deviceId
    deviceName = parsed.deviceName
    if (!registered) needsRegistration = true
  }

  function toggleConnection() {
    if (!canToggle) return
    if (active) disconnect()
    else connect()
  }

  function connect() {
    if (!canToggle) return
    if (!registered) {
      register()
      return
    }
    _desired = 1
    runAction(["connect"], "Connecting…")
  }

  function disconnect() {
    if (!canToggle) return
    _desired = 0
    runAction(["disconnect"], "Disconnecting…")
  }

  function register() {
    if (!installed || daemonDown || actionProcess.running) return
    _desired = -1
    runAction(["registration", "new"], "Registering device…")
  }

  function setMode(value) {
    var next = String(value || "")
    if (!installed || daemonDown || next === "" || actionProcess.running) return
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
    if (!installed || daemonDown || next === "" || actionProcess.running) return
    runAction(["dns", "families", next], "DNS filtering: " + next)
  }

  function startDaemon() {
    if (daemonProcess.running) return
    actionStatus = "Starting WARP daemon…"
    daemonProcess.command = ["bash", "-c", "sudo -n systemctl start warp-svc 2>/dev/null || pkexec systemctl start warp-svc"]
    daemonProcess.running = true
  }

  function stopDaemon() {
    if (daemonProcess.running) return
    actionStatus = "Stopping WARP daemon…"
    daemonProcess.command = ["bash", "-c", "sudo -n systemctl stop warp-svc 2>/dev/null || pkexec systemctl stop warp-svc"]
    daemonProcess.running = true
  }

  function runAction(args, label) {
    if (actionProcess.running) return
    actionStatus = label || ""
    actionProcess.command = warpCommand(args)
    actionProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.installed || !root.probed
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: root.installed || !root.probed
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
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      root.applyStatus(String(statusStdout.text || root._statusOutput || ""), exitCode, String(statusStderr.text || root._statusError || ""))
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
      root.applyRegistration(String(registrationStdout.text || registrationStderr.text || ""))
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
      var stderr = String(actionStderr.text || "")
      var failed = exitCode !== 0 || Model.errorCode(stdout) !== ""
      if (failed) {
        root._desired = -1
        root.lastError = Model.errorMessage(stdout || stderr) || "warp-cli command failed"
        root.flash(root.lastError)
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastRegistrationMs = 0
        Quickshell.execDetached(warpCommand(["debug", "connectivity-check", "disable"]))
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
      if (exitCode !== 0) {
        root.lastError = Model.elide(String(daemonStderr.text || daemonStdout.text || "Could not manage warp-svc"))
        root.flash(root.lastError)
      } else {
        root.lastError = ""
        root.flash("WARP daemon updated")
        Quickshell.execDetached(warpCommand(["debug", "connectivity-check", "disable"]))
      }
      delayedRefresh.restart()
      settleRefresh.restart()
    }
  }
}
