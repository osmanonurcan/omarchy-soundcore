// Setting types the panel can change, and reads the values of; keep in step
// with soundcore-status.
var CONTROL_TYPES = ["select", "optionalSelect", "modifiableSelect", "toggle", "i32Range", "equalizer",
  "hueColorPicker", "multiSelectWithRemove"]
// Also shown: read-only information, and actions, which have no value.
var SHOWN_TYPES = CONTROL_TYPES.concat(["information", "action"])

// The categories the panel lays out itself; every other one is a section.
var OWN_CATEGORIES = ["soundModes", "equalizer"]

var SECTION_TITLES = {
  buttonConfiguration: "Touch controls",
  limitHighVolume: "Volume limit",
  miscellaneous: "Other settings",
  deviceInformation: "About"
}

var LABELS = {
  ambientSoundMode: "Sound mode",
  noiseCancelingMode: "Noise canceling",
  manualNoiseCanceling: "Noise canceling strength",
  adaptiveNoiseCanceling: "Adaptive level",
  transportationMode: "Transportation",
  customNoiseCanceling: "Noise canceling strength",
  multiSceneNoiseCanceling: "Scene",
  adaptiveNoiseCancelingSensitivityLevel: "Adaptive sensitivity",
  realTimeAdaptiveNoiseCanceling: "Real-time adaptive noise canceling",
  ancPersonalizedToEarCanal: "ANC personalized to ear canal",
  windNoiseSuppression: "Wind noise reduction",
  transparencyMode: "Transparency",
  manualTransparency: "Transparency level",
  presetEqualizerProfile: "Equalizer preset",
  customEqualizerProfile: "My EQ profiles",
  volumeAdjustments: "Custom EQ",
  resetButtonsToDefault: "Reset to defaults",
  limitHighVolumeDbLimit: "Maximum volume",
  limitHighVolumeRefreshRate: "Volume check interval",
  autoPlayPause: "Auto play/pause",
  firmwareVersion: "Firmware",
  firmwareVersionLeft: "Firmware (left)",
  firmwareVersionRight: "Firmware (right)",
  twsStatus: "Earbud link",
  hostDevice: "Primary earbud",
  ldac: "LDAC",
  dolbyAudio: "Dolby Audio",
  incomingCallsDuringBluetoothMode: "Incoming calls in Bluetooth mode",
  noiseCancelingModeInCycle: "Noise canceling in button cycle",
  transparencyModeInCycle: "Transparency in button cycle",
  normalModeInCycle: "Normal in button cycle",
  lightsColor: "Color",
  dualConnectionsDevices: "Devices"
}

var UNITS = {
  limitHighVolumeDbLimit: " dB",
  lightsColor: "°"
}

// What the "none" value of an optional select means.
var NONE_LABELS = {
  presetEqualizerProfile: "Custom"
}

// When a setting applies, as the values other settings must have (or one of
// several). A sound mode setting not listed here whose id names a sound mode
// follows that mode.
var CONDITIONS = {
  noiseCancelingMode: { ambientSoundMode: "NoiseCanceling" },
  // The Space One calls its manual mode Custom.
  manualNoiseCanceling: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: ["Manual", "Custom"] },
  customNoiseCanceling: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Custom" },
  adaptiveNoiseCanceling: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Adaptive" },
  adaptiveNoiseCancelingSensitivityLevel: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Adaptive" },
  multiSceneNoiseCanceling: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "MultiScene" },
  transportationMode: { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Transportation" },
  windNoiseSuppression: { ambientSoundMode: "NoiseCanceling" },
  windNoiseDetected: { ambientSoundMode: "NoiseCanceling" },
  ancPersonalizedToEarCanal: { ambientSoundMode: "NoiseCanceling" },
  environmentDetection: { ambientSoundMode: "NoiseCanceling" },
  transparencyMode: { ambientSoundMode: "Transparency" },
  manualTransparency: { ambientSoundMode: "Transparency", transparencyMode: "Manual" },
  limitHighVolumeDbLimit: { limitHighVolume: true },
  limitHighVolumeRefreshRate: { limitHighVolume: true },
  lightsBrightness: { lightsEnabled: true },
  autoLightsOffMinutes: { lightsEnabled: true },
  lightsColor: { lightsEnabled: true },
  lightsMode: { lightsEnabled: true },
  // Headphones only report the devices they remember with these on.
  dualConnectionsDevices: { dualConnections: true }
}

// A tap on a touch control: which earbud, if the model has two, and how.
var PRESS = /^(left|right)?(single|double|triple|long)Press$/i
// Any touch control gesture, taps and slides alike.
var GESTURE = /^(left|right)?((single|double|triple|long)Press|slide(Up|Down))$/i

function parseStatus(raw) {
  try {
    var parsed = JSON.parse(raw || "{}")
    if (!parsed || typeof parsed !== "object") return { connected: false }
    if (!parsed.connected) return disconnected(parsed)
    return parsed
  } catch (e) {
    return { connected: false }
  }
}

// Not connected, saying so if openscq30-cli isn't installed, and naming the
// Soundcore device that is connected if openscq30 doesn't recognize it.
function disconnected(status) {
  var result = { connected: false }
  if (!status) return result
  if (status.missing === "openscq30-cli") result.missing = status.missing
  if (typeof status.unrecognized === "string" && status.unrecognized !== "")
    result.unrecognized = status.unrecognized.slice(0, 64)
  return result
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
  if (!next || !next.connected) return disconnected(next)
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

function isShown(setting) {
  if (!setting || SHOWN_TYPES.indexOf(setting.type) === -1) return false
  // The battery and charging state are in the panel's header.
  return !(setting.type === "information" && /battery|charging/i.test(setting.settingId))
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

function conditionsFor(settingId, categoryId) {
  if (CONDITIONS[settingId]) return CONDITIONS[settingId]
  if (categoryId !== "soundModes") return {}
  if (/noisecanceling/i.test(settingId)) return { ambientSoundMode: "NoiseCanceling" }
  if (/transparency/i.test(settingId)) return { ambientSoundMode: "Transparency" }
  return {}
}

// A setting applies unless a value it depends on is known to be different.
function applies(settingId, categoryId, values) {
  var conditions = conditionsFor(settingId, categoryId)
  for (var key in conditions) {
    var current = values ? values[key] : undefined
    if (current === undefined || current === null) continue
    var wanted = [].concat(conditions[key])
    if (wanted.indexOf(current) === -1) return false
  }
  return true
}

// The settings of a category to draw as rows, in the device's order.
function rowIds(schema, categoryId, values, skip) {
  var ids = []
  var settings = settingsIn(schema, categoryId)
  for (var i = 0; i < settings.length; i++) {
    var id = settings[i].settingId
    if (!isShown(settings[i]) || (skip && skip.indexOf(id) !== -1)) continue
    if (applies(id, categoryId, values)) ids.push(id)
  }
  return ids
}

// The categories drawn as their own sections, with their rows, in the
// device's order: every one but those the panel lays out itself, if it has
// anything to show.
function sections(schema, values) {
  var list = []
  for (var i = 0; i < (schema || []).length; i++) {
    var id = schema[i].categoryId
    if (OWN_CATEGORIES.indexOf(id) !== -1) continue
    var rows = rowIds(schema, id, values)
    if (rows.length) list.push({ id: id, title: SECTION_TITLES[id] || label(id), rows: rows })
  }
  return list
}

function label(settingId) {
  if (LABELS[settingId]) return LABELS[settingId]
  var gesture = PRESS.exec(settingId)
  if (gesture) {
    var side = gesture[1] ? gesture[1].toLowerCase() + " " : ""
    var kind = gesture[2].toLowerCase() === "long" ? "long press" : gesture[2].toLowerCase() + " tap"
    var text = side + kind
    return text.charAt(0).toUpperCase() + text.slice(1)
  }
  var words = String(settingId).replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase()
  return words.charAt(0).toUpperCase() + words.slice(1)
}

// openscq30 wraps numbers in its labels in invisible direction marks
// ("⁨10⁩ minutes"), which some fonts draw as boxes.
function plainLabel(text) {
  return String(text).replace(/[⁦-⁩]/g, "")
}

function buildOptions(setting) {
  if (!setting || !setting.setting || !Array.isArray(setting.setting.options)) return []
  var options = setting.setting.options
  var labels = setting.setting.localizedOptions || options
  var list = []
  for (var i = 0; i < options.length; i++) {
    list.push({
      value: String(options[i]),
      label: plainLabel(labels[i] !== undefined ? labels[i] : options[i])
    })
  }
  return list
}

// Options for a select. An optional select's "none" is offered only while
// it's the current value, so it shows what's active without being a choice
// that does something unexpected -- except for a touch control, where it
// means the gesture does nothing, a choice of its own.
function selectOptions(setting, current) {
  var list = buildOptions(setting)
  if (!setting || setting.type !== "optionalSelect" || !list.length) return list
  var gesture = GESTURE.test(setting.settingId)
  if (gesture || !current)
    list.unshift({ value: "", label: gesture ? "No action" : (NONE_LABELS[setting.settingId] || "None") })
  return list
}

function profileOptions(setting, current) {
  var list = buildOptions(setting)
  if (list.length && !current) list.unshift({ value: "", label: "Unsaved" })
  return list
}

// openscq30 accepts no changes to the EQ bands of a model without custom
// profiles (it reports them, so the active preset's curve can be shown), but
// doesn't say so in the schema.
function eqReadOnly(schema) {
  return !!findSetting(schema, "volumeAdjustments") && !findSetting(schema, "customEqualizerProfile")
}

function rangeOf(setting) {
  // A hue, in degrees.
  if (setting && setting.type === "hueColorPicker") return { min: 0, max: 359, step: 1, ticks: 360 }
  var range = (setting && setting.setting) || {}
  var min = Number(range.start) || 0
  var max = Number(range.end) || 0
  var step = Number(range.step) || 1
  return { min: min, max: max, step: step, ticks: Math.round((max - min) / step) + 1 }
}

function rangeText(settingId, value) {
  return String(value) + (UNITS[settingId] || "")
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

// Settings that can't both be on: turning one on makes the headphones turn
// the other off themselves, without telling openscq30, so a read over the
// same connection still has it on.
var EXCLUSIVE = {
  ldac: "dualConnections",
  dualConnections: "ldac"
}

// The models known to. Newer ones (the P42i, say) allow LDAC with two
// devices connected, so a model not here is left to the next read.
var EXCLUSIVE_MODELS = [
  "SoundcoreA3035", // Space One
  "SoundcoreA3040", // Space Q45
  "SoundcoreA3936", // Space A40
  "SoundcoreA3954"  // Liberty 4 Pro
]

// What turning a setting on turns off on `model`.
function exclusiveEffects(model, settingId, value) {
  var overlay = {}
  if (value === true && EXCLUSIVE[settingId] && EXCLUSIVE_MODELS.indexOf(model) !== -1)
    overlay[EXCLUSIVE[settingId]] = false
  return overlay
}

// What else a write changes on `model`, so the panel can show it before the
// device confirms. Picking a preset or saved profile sets the bands, which
// are known once that preset or profile has been seen; moving a band leaves
// both.
function writeEffects(settingId, value, bands, model) {
  var overlay = {}
  overlay[settingId] = value
  Object.assign(overlay, exclusiveEffects(model, settingId, value))
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
// values the panel shows until the device, a `model`, confirms them.
function writeEntry(setting, value, bands, model) {
  var id = setting.settingId
  // An action has no value to show, and like a profile command, must run
  // after the writes queued ahead of it and before those queued after.
  if (setting.type === "action") return { id: id, arg: "", overlay: {}, command: true }
  if (setting.type === "hueColorPicker") value = Math.round(Number(value) || 0)
  // openscq30 reads a leading + or - as save/delete; \ marks a plain name.
  var arg = setting.type === "modifiableSelect" ? "\\" + value : formatValue(value)
  return { id: id, arg: arg, overlay: writeEffects(id, value, bands || {}, model) }
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

// The device's status once soundcore-set has run the writes `sent`, given
// what it read back (null if it failed). A failed write changed nothing; the
// panel stops showing it as soon as it's no longer pending.
function afterWrite(device, sent, readBack) {
  if (!readBack) return device
  var values = Object.assign({}, readBack)
  for (var i = 0; i < sent.length; i++)
    Object.assign(values, exclusiveEffects(device.model, sent[i].id, sent[i].overlay[sent[i].id]))
  return withValues(device, values)
}

// Show writes that haven't been confirmed yet, so the panel reflects a click
// immediately instead of after the device round trip. `status` is the
// device's own; the writes are laid over a copy.
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

// ---- Dual connections ----

function reversedMac(mac) {
  return String(mac).split(":").reverse().join(":")
}

// The devices headphones with dual connections remember, by Bluetooth
// address: which are connected, and which is this computer (`adapter`).
// Some headphones (the Space Q45) report addresses byte-reversed, so this
// computer is recognized in either order.
function devices(setting, connected, adapter) {
  var list = buildOptions(setting)
  var on = (Array.isArray(connected) ? connected : []).map(function(mac) { return String(mac).toUpperCase() })
  var self = String(adapter || "").toUpperCase()
  return list.map(function(option) {
    var mac = option.value.toUpperCase()
    return {
      mac: option.value,
      name: option.label !== "" ? option.label : option.value,
      connected: on.indexOf(mac) !== -1,
      thisComputer: self !== "" && (mac === self || mac === reversedMac(self))
    }
  })
}

// Whether the headphones still list the device at `mac`.
function remembers(schema, settingId, mac) {
  var setting = findSetting(schema, settingId)
  return !!setting && !!setting.setting && Array.isArray(setting.setting.options)
    && setting.setting.options.indexOf(mac) !== -1
}

// Make the headphones forget a device. openscq30 reads a leading - as remove.
function forgetCommand(setting, mac) {
  return { id: setting.settingId, arg: "-" + mac, overlay: {}, command: true }
}

// Show an option gone from a setting before the next full read.
function withOptionRemoved(status, settingId, option) {
  if (!status || !Array.isArray(status.schema)) return status
  var schema = status.schema.map(function(category) {
    return Object.assign({}, category, {
      settings: (category.settings || []).map(function(setting) {
        if (setting.settingId !== settingId || !setting.setting || !Array.isArray(setting.setting.options)) return setting
        var index = setting.setting.options.indexOf(option)
        if (index === -1) return setting
        var options = setting.setting.options.slice()
        var labels = (setting.setting.localizedOptions || options).slice()
        options.splice(index, 1)
        labels.splice(index, 1)
        return Object.assign({}, setting, {
          setting: Object.assign({}, setting.setting, { options: options, localizedOptions: labels })
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
    "SoundcoreA3947": "Liberty 4 NC",
    "SoundcoreA3948": "A20i"
  }
  // The device's own name, in the title, says which one it is anyway.
  return known[model] || ""
}

// Battery levels, as the headphones report them: one for headphones, one per
// earbud and the case for earbuds.
var BATTERIES = [
  { level: "batteryLevel", charging: "isCharging", name: "" },
  { level: "batteryLevelLeft", charging: "isChargingLeft", name: "Left" },
  { level: "batteryLevelRight", charging: "isChargingRight", name: "Right" },
  { level: "caseBatteryLevel", charging: "isChargingCase", name: "Case" }
]

// The same icons, picked the same way, as Omarchy's own battery indicator.
var BATTERY_ICONS = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
var CHARGING_ICONS = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
var UNKNOWN_BATTERY_ICON = "󰂑"

function isCharging(value) {
  return value === true || /^(yes|true|charging)$/i.test(String(value))
}

// A level as openscq30 reports it ("3/5", "7/10", "85/100") in percent, or
// null if it isn't one.
function batteryPercent(level) {
  var match = /^\s*(\d+)\s*\/\s*(\d+)\s*$/.exec(String(level))
  if (!match || Number(match[2]) <= 0) return null
  return Math.max(0, Math.min(100, Math.round(Number(match[1]) / Number(match[2]) * 100)))
}

function batteries(values) {
  if (!values) return []
  var list = []
  for (var i = 0; i < BATTERIES.length; i++) {
    var battery = BATTERIES[i]
    var level = values[battery.level]
    if (level === undefined || level === null || level === "") continue
    var charging = isCharging(values[battery.charging])
    var percent = batteryPercent(level)
    var index = percent === null ? 0 : Math.max(0, Math.min(9, Math.floor(percent / 10)))
    list.push({
      name: battery.name,
      text: percent === null ? String(level) : percent + "%",
      icon: percent === null ? UNKNOWN_BATTERY_ICON : (charging ? CHARGING_ICONS : BATTERY_ICONS)[index],
      low: percent !== null && percent <= 20 && !charging
    })
  }
  return list
}

function batteryText(values) {
  return batteries(values).map(function(battery) {
    return (battery.name || "Battery") + " " + battery.text
  }).join(" · ")
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
    sections: sections,
    label: label,
    buildOptions: buildOptions,
    selectOptions: selectOptions,
    profileOptions: profileOptions,
    rangeOf: rangeOf,
    rangeText: rangeText,
    eqReadOnly: eqReadOnly,
    formatValue: formatValue,
    sameValue: sameValue,
    writeEntry: writeEntry,
    profileCommand: profileCommand,
    queueWrite: queueWrite,
    hasCommand: hasCommand,
    setArgs: setArgs,
    getArgs: getArgs,
    afterWrite: afterWrite,
    withPendingWrites: withPendingWrites,
    withProfileChange: withProfileChange,
    cleanProfileName: cleanProfileName,
    devices: devices,
    remembers: remembers,
    forgetCommand: forgetCommand,
    withOptionRemoved: withOptionRemoved,
    learnBands: learnBands,
    errorMessage: errorMessage,
    localPath: localPath,
    formatBandLabel: formatBandLabel,
    csvFromBands: csvFromBands,
    friendlyModel: friendlyModel,
    batteries: batteries,
    batteryText: batteryText
  }
}
