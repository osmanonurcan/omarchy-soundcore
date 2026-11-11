function parseStatus(raw) {
  try {
    var parsed = JSON.parse(raw || "{}")
    if (!parsed || typeof parsed !== "object" || !parsed.connected) return { connected: false }
    return parsed
  } catch (e) {
    return { connected: false }
  }
}

// Combine a freshly read status with the one on screen. A quick poll (no
// device connection) only says which device is connected, so the settings
// already read from that same device are kept; a full read that failed keeps
// them too, with the error attached, rather than collapsing the panel.
function mergeStatus(prev, next) {
  if (!next || !next.connected) return { connected: false }
  var sameDevice = !!(prev && prev.connected && prev.detailed && prev.mac === next.mac)
  if (!sameDevice) return next
  if (!next.detailed) return prev
  if (next.error) return Object.assign({}, prev, { error: next.error })
  return next
}

// Show writes that haven't been confirmed by a status read yet, so the panel
// reflects a click immediately instead of after the device round trip.
function withPendingWrites(status, inflight, queued) {
  if (!status || !status.connected) return status
  return Object.assign({}, status, {
    values: Object.assign({}, status.values, inflight, queued)
  })
}

function formatValue(value) {
  if (Array.isArray(value)) return csvFromBands(value)
  return value === null || value === undefined ? "" : String(value)
}

function sameValue(current, next) {
  if (current === undefined) return false
  return formatValue(current) === formatValue(next)
}

function setArgs(writes) {
  var args = []
  for (var id in writes) {
    if (Object.prototype.hasOwnProperty.call(writes, id)) args.push(id + "=" + formatValue(writes[id]))
  }
  return args
}

function errorMessage(stderr, exitCode) {
  var lines = String(stderr || "").split("\n").filter(function(line) { return line.trim() !== "" })
  var message = lines.length ? lines[lines.length - 1].trim().replace(/^Error:\s*/, "") : ""
  return (message || "exited with status " + exitCode).slice(0, 200)
}

function localPath(url) {
  return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
}

function buildOptions(setting) {
  if (!setting || !setting.setting || !Array.isArray(setting.setting.options)) return []
  var options = setting.setting.options
  var labels = setting.setting.localizedOptions || options
  var list = []
  for (var i = 0; i < options.length; i++) {
    list.push({
      value: String(options[i]),
      label: String(labels[i] !== undefined ? labels[i] : options[i])
    })
  }
  return list
}

// The preset is optional: with a custom EQ there is none, which openscq30
// reports as null and accepts back as an empty value.
function presetOptions(setting, current) {
  var list = buildOptions(setting)
  if (list.length && !current) list.unshift({ value: "", label: "Custom" })
  return list
}

function formatBandLabel(hz) {
  var n = Number(hz) || 0
  if (n >= 1000) {
    var khz = Math.round(n / 100) / 10
    return khz + "kHz"
  }
  return n + "Hz"
}

function csvFromBands(bands) {
  var parts = []
  for (var i = 0; i < bands.length; i++) {
    parts.push(String(Math.round(Number(bands[i]) || 0)))
  }
  return parts.join(",")
}

function friendlyModel(model) {
  var known = {
    "SoundcoreA3028": "Life Q30",
    "SoundcoreA3040": "Space Q45",
    "SoundcoreA3948": "A20i"
  }
  return known[model] || model || "Unknown model"
}

function batteryText(values) {
  if (!values) return ""
  var parts = []
  for (var key in values) {
    if (!Object.prototype.hasOwnProperty.call(values, key)) continue
    if (key.toLowerCase().indexOf("battery") === -1) continue
    var label = key.replace(/^battery/i, "").replace(/([A-Z])/g, " $1").trim()
    parts.push((label ? label + " " : "") + values[key])
  }
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    mergeStatus: mergeStatus,
    withPendingWrites: withPendingWrites,
    sameValue: sameValue,
    setArgs: setArgs,
    errorMessage: errorMessage,
    localPath: localPath,
    buildOptions: buildOptions,
    presetOptions: presetOptions,
    formatBandLabel: formatBandLabel,
    csvFromBands: csvFromBands,
    friendlyModel: friendlyModel,
    batteryText: batteryText
  }
}
