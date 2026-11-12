#!/usr/bin/env bash
# Exercises soundcore-status and soundcore-set against the fake openscq30-cli
# and bluetoothctl in tests/fake-bin. Run from anywhere: tests/scripts.test.sh
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mac=AA:BB:CC:DD:EE:FF
failures=0
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

# Fresh fake device state per test; also points the lock file at it. The
# device is a Space Q45 unless a fixture directory is given.
setup() {
  local fixture=${1:-$root/tests/fixtures}
  state=$(mktemp -d -p "$tmp_root")
  cp "$fixture/schema.json" "$fixture/values.json" "$state/"
  cp "$root/tests/fixtures/models.json" "$state/"
  echo "[{\"macAddress\":\"$mac\",\"model\":\"SoundcoreA3040\",\"isDemo\":false}]" >"$state/paired.json"
  export FAKE_SCQ_STATE=$state XDG_RUNTIME_DIR=$state
  export PATH="$root/tests/fake-bin:$PATH"
  unset FAKE_BT_NONE FAKE_BT_DEVICES FAKE_SCQ_DELAY SOUNDCORE_CALL_TIMEOUT SOUNDCORE_LOCK_TIMEOUT
}

# A Liberty 4 NC that openscq30 already knows.
setup_liberty() {
  setup "$root/tests/fixtures/liberty-4-nc"
  echo "[{\"macAddress\":\"$mac\",\"model\":\"SoundcoreA3947\",\"isDemo\":false}]" >"$state/paired.json"
  export FAKE_BT_DEVICES="Device $mac soundcore Liberty 4 NC"
}

paired_model() { jq -r --arg mac "$1" '.[] | select(.macAddress == $mac) | .model' "$state/paired.json"; }
calls_of() { touch "$state/calls.log"; grep -c "^$1" "$state/calls.log" || true; }
value() { jq -r --arg k "$1" '.[$k] | if type == "array" then join(",") else . end' "$state/values.json"; }
device_calls() { touch "$state/calls.log"; grep -c '^device ' "$state/calls.log" || true; }

check() {
  local name=$1
  shift
  if "$@"; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    failures=$((failures + 1))
  fi
}

t_no_device() {
  setup
  export FAKE_BT_NONE=1
  [ "$("$root/soundcore-status")" = '{"connected":false}' ]
}

t_full_status() {
  setup
  local out
  out=$("$root/soundcore-status") || return 1
  jq -e --arg mac "$mac" '
    .connected and .detailed and .mac == $mac and .name == "Soundcore Space Q45"
    and .model == "SoundcoreA3040" and (has("error") | not)
    and ([.schema[].categoryId] == ["soundModes", "equalizer", "deviceInformation"])
    and .values == {
      ambientSoundMode: "NoiseCanceling", transparencyMode: "Manual", noiseCancelingMode: "Adaptive",
      manualNoiseCanceling: 5, windNoiseSuppression: true, manualTransparency: 5,
      presetEqualizerProfile: "Lounge", customEqualizerProfile: null,
      volumeAdjustments: [-10,20,40,30,0,-20,20,10], batteryLevel: "4/5",
      serialNumber: "TEST000000000000", firmwareVersion: "02.61"
    }
  ' <<<"$out" >/dev/null
}

t_full_status_reads_every_category() {
  setup_liberty
  local out
  out=$("$root/soundcore-status") || return 1
  # Everything but the EQ import/export, which the panel has no use for, and
  # every value but the reset action's, which has none.
  jq -e --slurpfile want "$state/values.json" '
    .model == "SoundcoreA3947" and (has("error") | not)
    and ([.schema[].categoryId] == ["soundModes", "equalizer", "buttonConfiguration",
                                    "limitHighVolume", "miscellaneous", "deviceInformation"])
    and .values == $want[0]
  ' <<<"$out" >/dev/null && ! grep -q resetButtonsToDefault "$state/calls.log"
}

t_registers_a_new_soundcore_device() {
  setup
  export FAKE_BT_DEVICES="Device 11:22:33:44:55:66 soundcore Liberty 4 NC"
  local out
  out=$("$root/soundcore-status" --quick) || return 1
  jq -e '.connected and .mac == "11:22:33:44:55:66" and .model == "SoundcoreA3947"' <<<"$out" >/dev/null &&
    [ "$(paired_model 11:22:33:44:55:66)" = SoundcoreA3947 ] &&
    [ "$(paired_model "$mac")" = SoundcoreA3040 ]
}

t_registers_by_any_name_of_a_model() {
  setup
  export FAKE_BT_DEVICES="Device 11:22:33:44:55:66 Soundcore  Life Q30"
  "$root/soundcore-status" --quick >/dev/null || return 1
  [ "$(paired_model 11:22:33:44:55:66)" = SoundcoreA3028 ]
}

t_leaves_an_unknown_soundcore_device_alone() {
  setup
  export FAKE_BT_DEVICES="Device 11:22:33:44:55:66 soundcore Mystery 9"
  [ "$("$root/soundcore-status" --quick)" = '{"connected":false,"unrecognized":"soundcore Mystery 9"}' ] &&
    [ "$(calls_of "paired-devices add")" = 0 ]
}

t_does_not_guess_between_models_with_one_name() {
  setup
  export FAKE_BT_DEVICES="Device 11:22:33:44:55:66 Soundcore R50i"
  "$root/soundcore-status" --quick >/dev/null || return 1
  [ "$(calls_of "paired-devices add")" = 0 ]
}

t_ignores_other_bluetooth_devices() {
  setup
  export FAKE_BT_DEVICES="Device 11:22:33:44:55:66 MX Master 3"
  [ "$("$root/soundcore-status" --quick)" = '{"connected":false}' ] && [ "$(calls_of list-models)" = 0 ]
}

t_prefers_a_known_device_over_registering_another() {
  setup
  export FAKE_BT_DEVICES=$'Device 11:22:33:44:55:66 soundcore Mystery 9\nDevice AA:BB:CC:DD:EE:FF Soundcore Space Q45'
  local out
  out=$("$root/soundcore-status" --quick) || return 1
  jq -e --arg mac "$mac" '.connected and .mac == $mac and (has("unrecognized") | not)' <<<"$out" >/dev/null
}

t_quick_status_does_not_connect() {
  setup
  local out
  out=$("$root/soundcore-status" --quick) || return 1
  jq -e '.connected and .detailed == false and (has("schema") | not)' <<<"$out" >/dev/null &&
    [ "$(device_calls)" = 0 ]
}

t_status_reports_device_errors() {
  setup
  echo "Error: connection: other: Bluetooth operation not permitted: UUID already registered" >"$state/fail-next"
  local out
  out=$("$root/soundcore-status") || return 1
  jq -e '.connected and .detailed and .schema == [] and .values == {}
         and .error == "connection: other: Bluetooth operation not permitted: UUID already registered"' \
    <<<"$out" >/dev/null
}

# The bug PR #1 fixed: a set started while a status read holds the device.
t_set_during_status() {
  setup
  "$root/soundcore-status" >"$state/status.out" &
  local pid=$!
  sleep 0.2
  "$root/soundcore-set" "$mac" ambientSoundMode=Transparency >/dev/null 2>"$state/set.err" || return 1
  wait "$pid" || return 1
  jq -e .detailed "$state/status.out" >/dev/null && [ "$(value ambientSoundMode)" = Transparency ]
}

t_status_during_set() {
  setup
  "$root/soundcore-set" "$mac" ambientSoundMode=Transparency >/dev/null &
  local pid=$!
  sleep 0.2
  local out
  out=$("$root/soundcore-status") || return 1
  wait "$pid" || return 1
  jq -e '.values.ambientSoundMode == "Transparency" and (has("error") | not)' <<<"$out" >/dev/null
}

t_quick_status_does_not_wait_for_lock() {
  setup
  "$root/soundcore-set" "$mac" ambientSoundMode=Transparency >/dev/null &
  local pid=$! start end
  sleep 0.1
  start=$(date +%s%N)
  "$root/soundcore-status" --quick >/dev/null || return 1
  end=$(date +%s%N)
  wait "$pid"
  [ $(((end - start) / 1000000)) -lt 300 ]
}

t_set_applies_several_settings_in_one_connection() {
  setup
  "$root/soundcore-set" "$mac" ambientSoundMode=Transparency transparencyMode=TalkMode \
    windNoiseSuppression=false manualNoiseCanceling=3 \
    volumeAdjustments=10,-20,0,0,0,0,0,5 presetEqualizerProfile= >/dev/null || return 1
  [ "$(device_calls)" = 1 ] &&
    [ "$(value ambientSoundMode)" = Transparency ] &&
    [ "$(value transparencyMode)" = TalkMode ] &&
    [ "$(value windNoiseSuppression)" = false ] &&
    [ "$(value manualNoiseCanceling)" = 3 ] &&
    [ "$(value volumeAdjustments)" = "10,-20,0,0,0,0,0,5" ] &&
    [ "$(value presetEqualizerProfile)" = null ]
}

t_set_reads_back_after_writing() {
  setup
  local out
  out=$("$root/soundcore-set" "$mac" --get presetEqualizerProfile --get windNoiseSuppression \
    presetEqualizerProfile=Piano windNoiseSuppression=false) || return 1
  [ "$(device_calls)" = 1 ] &&
    [ "$out" = '{"presetEqualizerProfile":"Piano","windNoiseSuppression":false}' ]
}

t_set_without_read_back_prints_empty_object() {
  setup
  [ "$("$root/soundcore-set" "$mac" ambientSoundMode=Normal)" = '{}' ]
}

t_set_saves_selects_and_deletes_profiles() {
  setup
  "$root/soundcore-set" "$mac" 'customEqualizerProfile=+-Work' >/dev/null || return 1
  jq -e '.[1].settings[1].setting.options == ["-Work"]' "$state/schema.json" >/dev/null || return 1
  # The \ prefix selects a profile even when its name starts with + or -.
  "$root/soundcore-set" "$mac" 'customEqualizerProfile=\-Work' >/dev/null || return 1
  [ "$(value customEqualizerProfile)" = -Work ] || return 1
  "$root/soundcore-set" "$mac" 'customEqualizerProfile=--Work' >/dev/null || return 1
  [ "$(value customEqualizerProfile)" = null ] &&
    jq -e '.[1].settings[1].setting.options == []' "$state/schema.json" >/dev/null
}

t_set_reports_errors() {
  setup
  echo "Error: ambientSoundMode: invalid option" >"$state/fail-next"
  local rc=0
  "$root/soundcore-set" "$mac" ambientSoundMode=Bogus >/dev/null 2>"$state/set.err" || rc=$?
  [ "$rc" = 1 ] && grep -q "invalid option" "$state/set.err"
}

t_set_times_out_on_a_hung_device() {
  setup
  export FAKE_SCQ_DELAY=5 SOUNDCORE_CALL_TIMEOUT=1
  local rc=0
  "$root/soundcore-set" "$mac" ambientSoundMode=Normal >/dev/null 2>"$state/set.err" || rc=$?
  [ "$rc" = 124 ] && grep -q "timed out talking to the headphones" "$state/set.err"
}

t_set_gives_up_waiting_for_the_lock() {
  setup
  export SOUNDCORE_LOCK_TIMEOUT=1
  flock "$state/soundcore.lock" sleep 3 &
  local holder=$! rc=0
  sleep 0.1
  "$root/soundcore-set" "$mac" ambientSoundMode=Normal >/dev/null 2>"$state/set.err" || rc=$?
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  [ "$rc" = 1 ] && grep -q "timed out waiting" "$state/set.err" && [ "$(device_calls)" = 0 ]
}

t_set_usage() {
  setup
  local rc1=0 rc2=0 rc3=0
  "$root/soundcore-set" "$mac" >/dev/null 2>&1 || rc1=$?
  "$root/soundcore-set" "$mac" --get ambientSoundMode >/dev/null 2>&1 || rc2=$?
  "$root/soundcore-set" "$mac" ambientSoundMode=Normal --get >/dev/null 2>&1 || rc3=$?
  [ "$rc1" = 2 ] && [ "$rc2" = 2 ] && [ "$rc3" = 2 ] && [ "$(device_calls)" = 0 ]
}

check "no connected device reports disconnected" t_no_device
check "full status reads schema, values and battery" t_full_status
check "full status reads every category the panel shows" t_full_status_reads_every_category
check "--quick finds the device without connecting to it" t_quick_status_does_not_connect
check "a new Soundcore device is registered by its name" t_registers_a_new_soundcore_device
check "any of a model's names identifies it" t_registers_by_any_name_of_a_model
check "an unknown Soundcore device is reported, not registered" t_leaves_an_unknown_soundcore_device_alone
check "a name shared by two models registers neither" t_does_not_guess_between_models_with_one_name
check "other Bluetooth devices are ignored" t_ignores_other_bluetooth_devices
check "a known device wins over an unknown one" t_prefers_a_known_device_over_registering_another
check "status reports a failed device read as an error" t_status_reports_device_errors
check "set waits for an in-flight status read instead of failing" t_set_during_status
check "status waits for an in-flight set and sees its result" t_status_during_set
check "--quick does not wait on the device lock" t_quick_status_does_not_wait_for_lock
check "set applies several settings over one connection" t_set_applies_several_settings_in_one_connection
check "set reads settings back over the same connection" t_set_reads_back_after_writing
check "set without --get prints an empty object" t_set_without_read_back_prints_empty_object
check "set saves, selects and deletes custom EQ profiles" t_set_saves_selects_and_deletes_profiles
check "set exits non-zero with the reason on stderr" t_set_reports_errors
check "set gives up on a hung device" t_set_times_out_on_a_hung_device
check "set gives up waiting for a stuck lock holder" t_set_gives_up_waiting_for_the_lock
check "set rejects missing settings" t_set_usage

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
