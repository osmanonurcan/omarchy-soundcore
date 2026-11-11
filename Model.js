// Setting types the panel can show; keep in step with soundcore-status.
var CONTROL_TYPES = ["select", "optionalSelect", "modifiableSelect", "toggle", "i32Range", "equalizer"]

var LABELS = {
  ambientSoundMode: "Sound mode",
  noiseCancelingMode: "Noise canceling",
  manualNoiseCanceling: "Noise canceling strength",
  windNoiseSuppression: "Wind noise reduction",
  transparencyMode: "Transparency",
  manualTransparency: "Transparency level",
  presetEqualizerProfile: "Equalizer preset",
  customEqualizerProfile: "My EQ profiles",
  volumeAdjustments: "Custom EQ"
}

// What the "none" value of an optional select means.
var NONE_LABELS = {
  presetEqualizerProfile: "Custom"
}

// When a setting applies, as the values other settings must have. A setting
// not listed here whose id names a sound mode follows that mode.
var CONDITIONS = {
  noiseCancelingMode: { ambientSoundMode: "NoiseCanceling" },
  manualNoiseCanceling: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Manual" },
  windNoiseSuppression: { ambientSoundMode: "NoiseCanceling" },
  transparencyMode: { ambientSoundMode: "Transparency" },
  manualTransparency: { ambientSoundMode: "Transparency", transparencyMode: "Manual" }
}

function parseStatus(raw) {
  try {
    var parsed = JSON.parse(raw || "{}")
    if (!parsed || typeof parsed !== "object" || !parsed.connected) return { connected: false }
    return parsed
  } catch (e) {
    return { connected: false }
  }
}

// The values soundcore-set read back after writing, or null.
function parseValues(raw) {
  try {
    var parsed = JSON.parse(raw || "")
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null
  } catch (e) {
    return null
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

function withValues(status, values) {
  if (!status || !status.connected) return status
  return Object.assign({}, status, { values: Object.assign({}, status.values, values) })
}

// ---- Schema ----

function settingsIn(schema, categoryId) {
  for (var i = 0; i < (schema || []).length; i++)
    if (schema[i].categoryId === categoryId) return schema[i].settings || []
  return []
}

function findSetting(schema, settingId) {
  for (var i = 0; i < (schema || []).length; i++) {
    var settings = schema[i].settings || []
    for (var j = 0; j < settings.length; j++)
      if (settings[j].settingId === settingId) return settings[j]
  }
  return null
}

function isControl(setting) {
  return !!setting && CONTROL_TYPES.indexOf(setting.type) !== -1
}

function readableIds(schema) {
  var ids = []
  for (var i = 0; i < (schema || []).length; i++) {
    var settings = schema[i].settings || []
    for (var j = 0; j < settings.length; j++)
      if (isControl(settings[j])) ids.push(settings[j].settingId)
  }
  return ids
}

function conditionsFor(settingId) {
  if (CONDITIONS[settingId]) return CONDITIONS[settingId]
  if (/noisecanceling/i.test(settingId)) return { ambientSoundMode: "NoiseCanceling" }
  if (/transparency/i.test(settingId)) return { ambientSoundMode: "Transparency" }
  return {}
}

// A setting applies unless a value it depends on is known to be different.
function applies(settingId, values) {
  var conditions = conditionsFor(settingId)
  for (var key in conditions) {
    var current = values ? values[key] : undefined
    if (current !== undefined && current !== null && current !== conditions[key]) return false
  }
  return true
}

// The settings of a category to draw as rows, in the device's order.
function rowIds(schema, categoryId, values, skip) {
  var ids = []
  var settings = settingsIn(schema, categoryId)
  for (var i = 0; i < settings.length; i++) {
    var id = settings[i].settingId
    if (!isControl(settings[i]) || (skip && skip.indexOf(id) !== -1)) continue
    if (applies(id, values)) ids.push(id)
  }
  return ids
}

function label(settingId) {
  if (LABELS[settingId]) return LABELS[settingId]
  var words = String(settingId).replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase()
  return words.charAt(0).toUpperCase() + words.slice(1)
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

// Options for a select. An optional select's "none" is offered only while
// it's the current value, so it shows what's active without being a choice
// that does something unexpected.
function selectOptions(setting, current) {
  var list = buildOptions(setting)
  if (setting && setting.type === "optionalSelect" && list.length && !current)
    list.unshift({ value: "", label: NONE_LABELS[setting.settingId] || "None" })
  return list
}

function profileOptions(setting, current) {
  var list = buildOptions(setting)
  if (list.length && !current) list.unshift({ value: "", label: "Unsaved" })
  return list
}

function rangeOf(setting) {
  var range = (setting && setting.setting) || {}
  var min = Number(range.start) || 0
  var max = Number(range.end) || 0
  var step = Number(range.step) || 1
  return { min: min, max: max, step: step, ticks: Math.round((max - min) / step) + 1 }
}

// ---- Writes ----

function formatValue(value) {
  if (Array.isArray(value)) return csvFromBands(value)
  return value === null || value === undefined ? "" : String(value)
}

function sameValue(current, next) {
  if (current === undefined) return false
  return formatValue(current) === formatValue(next)
}

// What else a write changes, so the panel can show it before the device
// confirms. Picking a preset or saved profile sets the bands, which are
// known once that preset or profile has been seen; moving a band leaves
// both.
function writeEffects(settingId, value, bands) {
  var overlay = {}
  overlay[settingId] = value
  if (settingId === "presetEqualizerProfile" && value !== "") {
    overlay.customEqualizerProfile = null
    if (bands["preset:" + value]) overlay.volumeAdjustments = bands["preset:" + value]
  } else if (settingId === "customEqualizerProfile") {
    overlay.presetEqualizerProfile = null
    if (bands["custom:" + value]) overlay.volumeAdjustments = bands["custom:" + value]
  } else if (settingId === "volumeAdjustments") {
    overlay.presetEqualizerProfile = null
    overlay.customEqualizerProfile = null
  }
  return overlay
}

// A pending write: `arg` is the value soundcore-set sends, `overlay` the
// values the panel shows until the device confirms them.
function writeEntry(setting, value, bands) {
  var id = setting.settingId
  // openscq30 reads a leading + or - as save/delete; \ marks a plain name.
  var arg = setting.type === "modifiableSelect" ? "\\" + value : formatValue(value)
  return { id: id, arg: arg, overlay: writeEffects(id, value, bands || {}) }
}

// Save the current bands as profile `name`, or delete it. openscq30 reports a
// saved profile as active while no preset is and the bands match it.
function profileCommand(name, remove, values) {
  var overlay = {}
  if (remove && values.customEqualizerProfile === name) overlay.customEqualizerProfile = null
  if (!remove && !values.presetEqualizerProfile) overlay.customEqualizerProfile = name
  return { id: "customEqualizerProfile", arg: (remove ? "-" : "+") + name, overlay: overlay, command: true }
}

// Queue a write, replacing a queued write of the same setting, but never one
// before a command, which has to see the writes queued ahead of it.
function queueWrite(queue, entry) {
  var next = queue.slice()
  if (!entry.command) {
    for (var i = next.length - 1; i >= 0 && !next[i].command; i--) {
      if (next[i].id === entry.id) {
        next[i] = entry
        return next
      }
    }
  }
  next.push(entry)
  return next
}

function hasCommand(entries) {
  for (var i = 0; i < entries.length; i++) if (entries[i].command) return true
  return false
}

function setArgs(entries) {
  return entries.map(function(entry) { return entry.id + "=" + entry.arg })
}

function getArgs(ids) {
  var args = []
  for (var i = 0; i < ids.length; i++) args.push("--get", ids[i])
  return args
}

// Show writes that haven't been confirmed yet, so the panel reflects a click
// immediately instead of after the device round trip.
function withPendingWrites(status, inflight, queued) {
  if (!status || !status.connected) return status
  var values = Object.assign({}, status.values)
  var entries = inflight.concat(queued)
  for (var i = 0; i < entries.length; i++) Object.assign(values, entries[i].overlay)
  return Object.assign({}, status, { values: values })
}

// Show a saved or deleted profile in the list before the next full read.
function withProfileChange(status, name, remove) {
  if (!status || !Array.isArray(status.schema)) return status
  var schema = status.schema.map(function(category) {
    return Object.assign({}, category, {
      settings: (category.settings || []).map(function(setting) {
        if (setting.settingId !== "customEqualizerProfile" || !setting.setting) return setting
        var options = (setting.setting.options || []).filter(function(o) { return o !== name })
        if (!remove) options.push(name)
        return Object.assign({}, setting, {
          setting: Object.assign({}, setting.setting, { options: options, localizedOptions: options.slice() })
        })
      })
    })
  })
  return Object.assign({}, status, { schema: schema })
}

function cleanProfileName(name) {
  var trimmed = String(name || "").trim()
  return trimmed.length > 64 ? "" : trimmed
}

// Remember which bands a preset or saved profile sets, from values the
// device reported, so picking it again can move the sliders right away.
function learnBands(bands, values) {
  if (!values || !Array.isArray(values.volumeAdjustments)) return bands
  var key = values.presetEqualizerProfile ? "preset:" + values.presetEqualizerProfile
    : (values.customEqualizerProfile ? "custom:" + values.customEqualizerProfile : "")
  if (!key) return bands
  var next = Object.assign({}, bands)
  next[key] = values.volumeAdjustments.slice()
  return next
}

// ---- Display ----

function errorMessage(stderr, exitCode) {
  var lines = String(stderr || "").split("\n").filter(function(line) { return line.trim() !== "" })
  var message = lines.length ? lines[lines.length - 1].trim().replace(/^Error:\s*/, "") : ""
  return (message || "exited with status " + exitCode).slice(0, 200)
}

function localPath(url) {
  return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
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
    var part = key.replace(/^battery/i, "").replace(/([A-Z])/g, " $1").trim()
    parts.push((part ? part + " " : "") + values[key])
  }
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    parseValues: parseValues,
    mergeStatus: mergeStatus,
    withValues: withValues,
    settingsIn: settingsIn,
    findSetting: findSetting,
    readableIds: readableIds,
    rowIds: rowIds,
    label: label,
    buildOptions: buildOptions,
    selectOptions: selectOptions,
    profileOptions: profileOptions,
    rangeOf: rangeOf,
    formatValue: formatValue,
    sameValue: sameValue,
    writeEntry: writeEntry,
    profileCommand: profileCommand,
    queueWrite: queueWrite,
    hasCommand: hasCommand,
    setArgs: setArgs,
    getArgs: getArgs,
    withPendingWrites: withPendingWrites,
    withProfileChange: withProfileChange,
    cleanProfileName: cleanProfileName,
    learnBands: learnBands,
    errorMessage: errorMessage,
    localPath: localPath,
    formatBandLabel: formatBandLabel,
    csvFromBands: csvFromBands,
    friendlyModel: friendlyModel,
    batteryText: batteryText
  }
}
