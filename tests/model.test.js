const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const detailed = {
  connected: true,
  detailed: true,
  mac: "AA:BB:CC:DD:EE:FF",
  name: "Space Q45",
  model: "SoundcoreA3040",
  schema: [{ categoryId: "soundModes", settings: [] }],
  values: { ambientSoundMode: "Normal", volumeAdjustments: [0, 0, 0] }
}

test("parseStatus keeps the name of a connected device openscq30 doesn't recognize", () => {
  const raw = '{"connected":false,"unrecognized":"soundcore Mystery 9"}'
  assert.deepEqual(Model.parseStatus(raw), { connected: false, unrecognized: "soundcore Mystery 9" })
  assert.deepEqual(Model.mergeStatus(detailed, Model.parseStatus(raw)), { connected: false, unrecognized: "soundcore Mystery 9" })
  assert.deepEqual(Model.parseStatus('{"connected":false,"unrecognized":{"a":1}}'), { connected: false })
})

test("parseStatus keeps word that openscq30-cli isn't installed", () => {
  const raw = '{"connected":false,"missing":"openscq30-cli"}'
  assert.deepEqual(Model.parseStatus(raw), { connected: false, missing: "openscq30-cli" })
  assert.deepEqual(Model.mergeStatus(detailed, Model.parseStatus(raw)), { connected: false, missing: "openscq30-cli" })
  assert.deepEqual(Model.parseStatus('{"connected":false,"missing":"rm -rf"}'), { connected: false })
})

test("parseStatus treats unparseable output as disconnected", () => {
  assert.deepEqual(Model.parseStatus(""), { connected: false })
  assert.deepEqual(Model.parseStatus("not json"), { connected: false })
  assert.deepEqual(Model.parseStatus("null"), { connected: false })
})

test("mergeStatus: a quick poll of the same device keeps the settings already read", () => {
  const quick = { connected: true, detailed: false, mac: detailed.mac, name: "Space Q45", model: detailed.model }
  assert.equal(Model.mergeStatus(detailed, quick), detailed)
})

test("mergeStatus: a quick poll of a different device replaces the status", () => {
  const quick = { connected: true, detailed: false, mac: "11:22:33:44:55:66", name: "Other", model: "SoundcoreA3028" }
  assert.equal(Model.mergeStatus(detailed, quick), quick)
})

test("mergeStatus: disconnecting replaces the status", () => {
  assert.deepEqual(Model.mergeStatus(detailed, { connected: false }), { connected: false })
})

test("mergeStatus: a failed read of the same device keeps the old settings and reports the error", () => {
  const failed = Object.assign({}, detailed, { schema: [], values: {}, error: "UUID already registered" })
  const merged = Model.mergeStatus(detailed, failed)
  assert.deepEqual(merged.schema, detailed.schema)
  assert.deepEqual(merged.values, detailed.values)
  assert.equal(merged.error, "UUID already registered")
})

test("mergeStatus: a successful read clears an earlier error", () => {
  const prev = Object.assign({}, detailed, { error: "boom" })
  const next = Object.assign({}, detailed, { values: { ambientSoundMode: "Transparency" } })
  const merged = Model.mergeStatus(prev, next)
  assert.equal(merged.error, undefined)
  assert.equal(merged.values.ambientSoundMode, "Transparency")
})

test("sameValue compares what the panel shows with what the user picked", () => {
  assert.equal(Model.sameValue("Normal", "Normal"), true)
  assert.equal(Model.sameValue("Normal", "Transparency"), false)
  assert.equal(Model.sameValue([1, 2, 3], [1, 2, 3]), true)
  assert.equal(Model.sameValue([1, 2, 3], [1, 2, 4]), false)
  assert.equal(Model.sameValue(null, ""), true, "no preset == Custom")
  assert.equal(Model.sameValue(undefined, "Normal"), false, "unknown current value never skips a write")
})

test("errorMessage keeps the last stderr line without the Error: prefix", () => {
  const stderr = "\nError: connection: other: Bluetooth operation not permitted: UUID already registered\n"
  assert.equal(Model.errorMessage(stderr, 1), "connection: other: Bluetooth operation not permitted: UUID already registered")
})

test("errorMessage falls back to the exit status and bounds long output", () => {
  assert.equal(Model.errorMessage("", 3), "exited with status 3")
  assert.equal(Model.errorMessage("Error: " + "x".repeat(1000), 1).length, 200)
})

test("localPath turns a resolved file URL into a filesystem path", () => {
  assert.equal(Model.localPath("file:///home/me/my%20plugins/soundcore-set"), "/home/me/my plugins/soundcore-set")
})

test("friendlyModel names known models and falls back to the id", () => {
  assert.equal(Model.friendlyModel("SoundcoreA3040"), "Space Q45")
  assert.equal(Model.friendlyModel("SoundcoreA3947"), "Liberty 4 NC")
  assert.equal(Model.friendlyModel("SoundcoreA9999"), "SoundcoreA9999")
  assert.equal(Model.friendlyModel(""), "Unknown model")
})

// ---- The Space Q45's real schema, as soundcore-status filters it ----
const fixture = require("./fixtures/schema.json")
const schema = fixture.filter((c) => c.categoryId === "soundModes" || c.categoryId === "equalizer")
const setting = (id) => Model.findSetting(schema, id)

test("readableIds lists the settings the panel can show, in the device's order", () => {
  assert.deepEqual(Model.readableIds(schema), [
    "ambientSoundMode", "transparencyMode", "noiseCancelingMode", "manualNoiseCanceling",
    "windNoiseSuppression", "manualTransparency",
    "presetEqualizerProfile", "customEqualizerProfile", "volumeAdjustments"
  ])
  assert.deepEqual(Model.readableIds(fixture).includes("importCustomEqualizerProfiles"), false)
})

test("rowIds shows noise canceling settings only in noise canceling mode", () => {
  assert.deepEqual(
    Model.rowIds(schema, "soundModes", { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Adaptive" }),
    ["ambientSoundMode", "noiseCancelingMode", "windNoiseSuppression"])
  assert.deepEqual(
    Model.rowIds(schema, "soundModes", { ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Manual" }),
    ["ambientSoundMode", "noiseCancelingMode", "manualNoiseCanceling", "windNoiseSuppression"])
})

test("rowIds shows transparency settings only in transparency mode", () => {
  assert.deepEqual(
    Model.rowIds(schema, "soundModes", { ambientSoundMode: "Transparency", transparencyMode: "Manual" }),
    ["ambientSoundMode", "transparencyMode", "manualTransparency"])
  assert.deepEqual(
    Model.rowIds(schema, "soundModes", { ambientSoundMode: "Transparency", transparencyMode: "TalkMode" }),
    ["ambientSoundMode", "transparencyMode"])
  assert.deepEqual(Model.rowIds(schema, "soundModes", { ambientSoundMode: "Normal" }), ["ambientSoundMode"])
})

test("rowIds shows everything while the controlling values are unknown", () => {
  assert.equal(Model.rowIds(schema, "soundModes", {}).length, 6)
})

test("rowIds places settings it doesn't know by the sound mode their id names", () => {
  const other = [{ categoryId: "soundModes", settings: [
    { settingId: "ambientSoundMode", type: "select", setting: { options: ["NoiseCanceling", "Normal"] } },
    { settingId: "customNoiseCanceling", type: "i32Range", setting: { start: 0, end: 10, step: 1 } },
    { settingId: "fancyNewThing", type: "toggle" },
    { settingId: "someInformation", type: "information" }
  ] }]
  assert.deepEqual(Model.rowIds(other, "soundModes", { ambientSoundMode: "Normal" }),
    ["ambientSoundMode", "fancyNewThing", "someInformation"])
  assert.deepEqual(Model.rowIds(other, "soundModes", { ambientSoundMode: "NoiseCanceling" }),
    ["ambientSoundMode", "customNoiseCanceling", "fancyNewThing", "someInformation"])
})

test("rowIds leaves out the settings the panel draws itself", () => {
  assert.deepEqual(Model.rowIds(schema, "equalizer", {}, ["customEqualizerProfile", "volumeAdjustments"]),
    ["presetEqualizerProfile"])
})

test("label names known settings and spells out the rest", () => {
  assert.equal(Model.label("windNoiseSuppression"), "Wind noise reduction")
  assert.equal(Model.label("fancyNewThing"), "Fancy new thing")
  assert.equal(Model.label("leftSinglePress"), "Left single tap")
  assert.equal(Model.label("rightLongPress"), "Right long press")
  assert.equal(Model.label("doublePress"), "Double tap")
})

test("selectOptions offers the none choice of an optional select only while it's active", () => {
  const preset = setting("presetEqualizerProfile")
  assert.deepEqual(Model.selectOptions(preset, "Piano")[0], { value: "SoundcoreSignature", label: "Soundcore Signature" })
  assert.deepEqual(Model.selectOptions(preset, null)[0], { value: "", label: "Custom" })
  assert.deepEqual(Model.selectOptions(setting("ambientSoundMode"), "Normal").map((o) => o.value),
    ["NoiseCanceling", "Transparency", "Normal"])
  assert.deepEqual(Model.selectOptions(null, ""), [])
})

test("profileOptions marks EQ that isn't a saved profile as unsaved", () => {
  const custom = { settingId: "customEqualizerProfile", type: "modifiableSelect", setting: { options: ["Work"], localizedOptions: ["Work"] } }
  assert.deepEqual(Model.profileOptions(custom, "Work"), [{ value: "Work", label: "Work" }])
  assert.deepEqual(Model.profileOptions(custom, null), [{ value: "", label: "Unsaved" }, { value: "Work", label: "Work" }])
})

test("rangeOf reads an i32Range", () => {
  assert.deepEqual(Model.rangeOf(setting("manualNoiseCanceling")), { min: 1, max: 5, step: 1, ticks: 5 })
  assert.deepEqual(Model.rangeOf({ setting: { start: 75, end: 100, step: 5 } }), { min: 75, max: 100, step: 5, ticks: 6 })
})

test("writeEntry formats the value openscq30 expects for each type", () => {
  assert.equal(Model.writeEntry(setting("windNoiseSuppression"), false, {}).arg, "false")
  assert.equal(Model.writeEntry(setting("manualNoiseCanceling"), 3, {}).arg, "3")
  assert.equal(Model.writeEntry(setting("volumeAdjustments"), [1, -2.4], {}).arg, "1,-2")
  assert.equal(Model.writeEntry(setting("presetEqualizerProfile"), "", {}).arg, "")
  assert.equal(Model.writeEntry(setting("customEqualizerProfile"), "-Work", {}).arg, "\\-Work",
    "selecting a profile is escaped so a name starting with + or - isn't a command")
})

test("writeEntry: picking a preset shows the bands it set before, if known", () => {
  const bands = { "preset:Lounge": [-10, 20, 40, 30, 0, -20, 20, 10] }
  assert.deepEqual(Model.writeEntry(setting("presetEqualizerProfile"), "Lounge", bands).overlay, {
    presetEqualizerProfile: "Lounge", customEqualizerProfile: null, volumeAdjustments: bands["preset:Lounge"]
  })
  assert.deepEqual(Model.writeEntry(setting("presetEqualizerProfile"), "Rock", bands).overlay, {
    presetEqualizerProfile: "Rock", customEqualizerProfile: null
  })
})

test("writeEntry: picking a saved profile or moving a band leaves the preset", () => {
  const bands = { "custom:Work": [1, 2, 3] }
  assert.deepEqual(Model.writeEntry(setting("customEqualizerProfile"), "Work", bands).overlay, {
    customEqualizerProfile: "Work", presetEqualizerProfile: null, volumeAdjustments: [1, 2, 3]
  })
  assert.deepEqual(Model.writeEntry(setting("volumeAdjustments"), [0, 0], bands).overlay, {
    volumeAdjustments: [0, 0], presetEqualizerProfile: null, customEqualizerProfile: null
  })
})

test("learnBands remembers what a preset or saved profile sets", () => {
  const bands = Model.learnBands({}, { presetEqualizerProfile: "Piano", customEqualizerProfile: null, volumeAdjustments: [0, 30] })
  assert.deepEqual(bands, { "preset:Piano": [0, 30] })
  assert.deepEqual(Model.learnBands(bands, { presetEqualizerProfile: null, customEqualizerProfile: "Work", volumeAdjustments: [5] }),
    { "preset:Piano": [0, 30], "custom:Work": [5] })
  assert.equal(Model.learnBands(bands, { presetEqualizerProfile: null, customEqualizerProfile: null, volumeAdjustments: [9] }), bands)
})

test("queueWrite replaces a queued write of the same setting in place", () => {
  const a = Model.writeEntry(setting("ambientSoundMode"), "Normal", {})
  const b = Model.writeEntry(setting("windNoiseSuppression"), true, {})
  const c = Model.writeEntry(setting("ambientSoundMode"), "Transparency", {})
  assert.deepEqual(Model.setArgs(Model.queueWrite(Model.queueWrite(Model.queueWrite([], a), b), c)),
    ["ambientSoundMode=Transparency", "windNoiseSuppression=true"])
})

test("queueWrite never moves a write across a profile command", () => {
  const save = Model.profileCommand("Work", false, {})
  let queue = Model.queueWrite([], Model.writeEntry(setting("presetEqualizerProfile"), "Rock", {}))
  queue = Model.queueWrite(queue, save)
  queue = Model.queueWrite(queue, Model.writeEntry(setting("presetEqualizerProfile"), "Jazz", {}))
  queue = Model.queueWrite(queue, Model.profileCommand("Work", false, {}))
  assert.deepEqual(Model.setArgs(queue), [
    "presetEqualizerProfile=Rock", "customEqualizerProfile=+Work",
    "presetEqualizerProfile=Jazz", "customEqualizerProfile=+Work"
  ])
})

test("profileCommand: deleting the active profile shows it as unsaved", () => {
  assert.deepEqual(Model.profileCommand("Work", true, { customEqualizerProfile: "Work" }).overlay, { customEqualizerProfile: null })
  assert.deepEqual(Model.profileCommand("Work", true, { customEqualizerProfile: "Home" }).overlay, {})
  assert.equal(Model.profileCommand("Work", true, {}).arg, "-Work")
})

test("profileCommand: saving custom bands shows them as the saved profile", () => {
  assert.deepEqual(Model.profileCommand("Work", false, { presetEqualizerProfile: null }).overlay, { customEqualizerProfile: "Work" })
  assert.deepEqual(Model.profileCommand("Work", false, { presetEqualizerProfile: "Rock" }).overlay, {},
    "openscq30 only reports a saved profile as active while no preset is")
  assert.equal(Model.profileCommand("Work", false, {}).arg, "+Work")
})

test("withProfileChange adds or removes a saved profile from the schema", () => {
  const status = { connected: true, schema, values: {} }
  const saved = Model.withProfileChange(status, "Work", false)
  assert.deepEqual(Model.findSetting(saved.schema, "customEqualizerProfile").setting.options, ["Work"])
  assert.deepEqual(Model.findSetting(Model.withProfileChange(saved, "Work", false).schema, "customEqualizerProfile").setting.options, ["Work"])
  assert.deepEqual(Model.findSetting(Model.withProfileChange(saved, "Work", true).schema, "customEqualizerProfile").setting.localizedOptions, [])
  assert.deepEqual(setting("customEqualizerProfile").setting.options, [], "input must not be mutated")
})

test("withPendingWrites overlays in-flight then queued writes", () => {
  const status = { connected: true, values: { ambientSoundMode: "Normal", windNoiseSuppression: true } }
  const merged = Model.withPendingWrites(status,
    [Model.writeEntry(setting("ambientSoundMode"), "Transparency", {})],
    [Model.writeEntry(setting("ambientSoundMode"), "NoiseCanceling", {})])
  assert.deepEqual(merged.values, { ambientSoundMode: "NoiseCanceling", windNoiseSuppression: true })
  assert.equal(status.values.ambientSoundMode, "Normal", "input must not be mutated")
  assert.deepEqual(Model.withPendingWrites({ connected: false }, [], []), { connected: false })
})

test("withValues applies values read back after a write", () => {
  const status = { connected: true, values: { a: 1, b: 2 } }
  assert.deepEqual(Model.withValues(status, { b: 3 }).values, { a: 1, b: 3 })
})

test("getArgs asks soundcore-set to read settings back", () => {
  assert.deepEqual(Model.getArgs(["a", "b"]), ["--get", "a", "--get", "b"])
})

test("parseValues accepts only a JSON object", () => {
  assert.deepEqual(Model.parseValues('{"a":1}\n'), { a: 1 })
  assert.equal(Model.parseValues("[]"), null)
  assert.equal(Model.parseValues(""), null)
  assert.equal(Model.parseValues("nope"), null)
})

test("cleanProfileName trims names and refuses empty or overlong ones", () => {
  assert.equal(Model.cleanProfileName("  Work  "), "Work")
  assert.equal(Model.cleanProfileName("   "), "")
  assert.equal(Model.cleanProfileName("x".repeat(65)), "")
})

// ---- The Liberty 4 NC's real schema and values, as soundcore-status reads them ----
const liberty = require("./fixtures/liberty-4-nc/schema.json").filter((c) => c.categoryId !== "equalizerImportExport")
const libertyValues = require("./fixtures/liberty-4-nc/values.json")
const libertySetting = (id) => Model.findSetting(liberty, id)
const soundRows = (values) => Model.rowIds(liberty, "soundModes", Object.assign({}, libertyValues, values))

test("rowIds shows each noise canceling mode's own settings", () => {
  assert.deepEqual(soundRows({ ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Adaptive" }),
    ["ambientSoundMode", "noiseCancelingMode", "adaptiveNoiseCanceling", "windNoiseSuppression", "environmentDetection"])
  assert.deepEqual(soundRows({ ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Manual" }),
    ["ambientSoundMode", "noiseCancelingMode", "manualNoiseCanceling", "windNoiseSuppression", "environmentDetection"])
  assert.deepEqual(soundRows({ ambientSoundMode: "NoiseCanceling", noiseCancelingMode: "Transportation" }),
    ["ambientSoundMode", "noiseCancelingMode", "transportationMode", "windNoiseSuppression", "environmentDetection"])
})

test("rowIds leaves noise canceling settings out of the other sound modes", () => {
  assert.deepEqual(soundRows({ ambientSoundMode: "Transparency" }), ["ambientSoundMode", "transparencyMode"])
  assert.deepEqual(soundRows({ ambientSoundMode: "Normal" }), ["ambientSoundMode"])
})

test("sections lists every other category with something to show, in the device's order", () => {
  assert.deepEqual(Model.sections(liberty, libertyValues), [
    { id: "buttonConfiguration", title: "Touch controls", rows: [
      "leftSinglePress", "rightSinglePress", "leftDoublePress", "rightDoublePress",
      "leftLongPress", "rightLongPress", "leftTriplePress", "rightTriplePress", "resetButtonsToDefault"] },
    { id: "limitHighVolume", title: "Volume limit", rows: ["limitHighVolume"] },
    { id: "miscellaneous", title: "Other settings", rows: [
      "touchTone", "gamingMode", "soundLeakCompensation", "surroundSound", "autoPlayPause",
      "wearingTone", "touchLock", "lowBatteryPrompt", "autoPowerOff"] },
    { id: "deviceInformation", title: "About", rows: [
      "serialNumber", "firmwareVersionLeft", "firmwareVersionRight", "twsStatus", "hostDevice"] }
  ])
})

test("sections shows the volume limit's settings only while it's on", () => {
  const on = Model.sections(liberty, Object.assign({}, libertyValues, { limitHighVolume: true }))
  assert.deepEqual(on[1].rows, ["limitHighVolume", "limitHighVolumeDbLimit", "limitHighVolumeRefreshRate"])
})

test("sections names categories it doesn't know and skips empty ones", () => {
  const other = [
    { categoryId: "soundModes", settings: [{ settingId: "ambientSoundMode", type: "select" }] },
    { categoryId: "fancyNewCategory", settings: [{ settingId: "noiseCancelingModeInCycle", type: "toggle" }] },
    { categoryId: "nothingToShow", settings: [{ settingId: "someList", type: "multiSelect" }] }
  ]
  // Only a sound mode setting follows the sound mode its id names.
  assert.deepEqual(Model.sections(other, { ambientSoundMode: "Normal" }),
    [{ id: "fancyNewCategory", title: "Fancy new category", rows: ["noiseCancelingModeInCycle"] }])
})

test("selectOptions always offers no action for a touch control", () => {
  const press = libertySetting("leftSinglePress")
  assert.deepEqual(Model.selectOptions(press, "PlayPause")[0], { value: "", label: "No action" })
  assert.deepEqual(Model.selectOptions(press, null)[0], { value: "", label: "No action" })
  assert.equal(Model.selectOptions(press, null).length, 8)
})

test("buildOptions drops the invisible direction marks openscq30 puts around numbers", () => {
  assert.deepEqual(Model.buildOptions(libertySetting("autoPowerOff")).map((o) => o.label),
    ["Disabled", "10 minutes", "20 minutes", "30 minutes", "60 minutes"])
})

test("writeEntry runs an action without showing a value for it", () => {
  const entry = Model.writeEntry(libertySetting("resetButtonsToDefault"), "", {})
  assert.deepEqual(entry, { id: "resetButtonsToDefault", arg: "", overlay: {}, command: true })
})

test("readableIds leaves out actions and information", () => {
  const ids = Model.readableIds(liberty)
  assert.equal(ids.includes("resetButtonsToDefault"), false)
  assert.equal(ids.includes("firmwareVersionLeft"), false)
  assert.equal(ids.includes("leftSinglePress"), true)
})

test("rangeText adds the unit a range is in", () => {
  assert.equal(Model.rangeText("limitHighVolumeDbLimit", 90), "90 dB")
  assert.equal(Model.rangeText("manualNoiseCanceling", 3), "3")
})

test("batteryText names each earbud and the case, and marks one charging", () => {
  assert.equal(Model.batteryText(libertyValues), "L 3/5 · R 2/5 · Case 3/5")
  assert.equal(Model.batteryText({ batteryLevelLeft: "3/5", isChargingLeft: "Yes", batteryLevelRight: "2/5", isChargingRight: "No" }),
    "L 3/5 (charging) · R 2/5")
  assert.equal(Model.batteryText({ batteryLevel: "4/5", firmwareVersion: "02.61" }), "Battery 4/5")
  assert.equal(Model.batteryText({ batteryLevel: "4/5", isCharging: true }), "Battery 4/5 (charging)")
  assert.equal(Model.batteryText({}), "")
})
