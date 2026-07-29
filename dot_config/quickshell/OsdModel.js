.pragma library

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
  if (n === "volume-low") return ""
  if (n === "volume-medium") return ""
  if (n === "volume-high" || n === "volume") return ""
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
  if (n === "microphone" || n === "mic") return "󰍬"
  if (n === "keyboard") return "󰌌"
  if (n === "brightness" || n === "display") return "󰍹"
  if (n === "touchpad") return "󰟸"
  if (n === "touch" || n === "touchscreen") return "󰜉"
  if (n.length > 0) return name
  if (percent <= 0) return ""
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? Math.max(0, Math.min(parsedValue, maxValue)) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    icon: iconFor(iconName, percent),
    message: String(rawMessage || (hasProgress ? (rawProgressText || percent + "%") : "")),
    value: value,
    maxValue: maxValue,
    hasProgress: hasProgress,
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}
