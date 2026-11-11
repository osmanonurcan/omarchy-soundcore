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

test("withPendingWrites overlays in-flight and queued writes, queued winning", () => {
  const status = Model.withPendingWrites(detailed,
    { ambientSoundMode: "Transparency", noiseCancelingMode: "Indoor" },
    { ambientSoundMode: "NoiseCanceling" })
  assert.equal(status.values.ambientSoundMode, "NoiseCanceling")
  assert.equal(status.values.noiseCancelingMode, "Indoor")
  assert.deepEqual(status.values.volumeAdjustments, [0, 0, 0])
  assert.equal(detailed.values.ambientSoundMode, "Normal", "input must not be mutated")
})

test("withPendingWrites leaves a disconnected status alone", () => {
  const status = { connected: false }
  assert.equal(Model.withPendingWrites(status, { a: "1" }, {}), status)
})

test("setArgs formats each write as settingId=value, bands as integer CSV", () => {
  assert.deepEqual(
    Model.setArgs({ ambientSoundMode: "Transparency", volumeAdjustments: [10, -20.4, 0], presetEqualizerProfile: "" }),
    ["ambientSoundMode=Transparency", "volumeAdjustments=10,-20,0", "presetEqualizerProfile="]
  )
})

test("sameValue compares what the panel shows with what the user picked", () => {
  assert.equal(Model.sameValue("Normal", "Normal"), true)
  assert.equal(Model.sameValue("Normal", "Transparency"), false)
  assert.equal(Model.sameValue([1, 2, 3], [1, 2, 3]), true)
  assert.equal(Model.sameValue([1, 2, 3], [1, 2, 4]), false)
  assert.equal(Model.sameValue(null, ""), true, "no preset == Custom")
  assert.equal(Model.sameValue(undefined, "Normal"), false, "unknown current value never skips a write")
})

test("presetOptions offers Custom only while no preset is active", () => {
  const setting = { setting: { options: ["Acoustic"], localizedOptions: ["Acoustic"] } }
  assert.deepEqual(Model.presetOptions(setting, "Acoustic"), [{ value: "Acoustic", label: "Acoustic" }])
  assert.deepEqual(Model.presetOptions(setting, ""), [
    { value: "", label: "Custom" },
    { value: "Acoustic", label: "Acoustic" }
  ])
  assert.deepEqual(Model.presetOptions(null, ""), [])
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
  assert.equal(Model.friendlyModel("SoundcoreA9999"), "SoundcoreA9999")
  assert.equal(Model.friendlyModel(""), "Unknown model")
})
