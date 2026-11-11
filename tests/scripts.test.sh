#!/usr/bin/env bash
# Exercises soundcore-status and soundcore-set against the fake openscq30-cli
# and bluetoothctl in tests/fake-bin. Run from anywhere: tests/scripts.test.sh
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mac=AA:BB:CC:DD:EE:FF
failures=0
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

# Fresh fake device state per test; also points the lock file at it.
setup() {
  state=$(mktemp -d -p "$tmp_root")
  cp "$root/tests/fixtures/schema.json" "$root/tests/fixtures/values.json" "$state/"
  export FAKE_SCQ_STATE=$state XDG_RUNTIME_DIR=$state
  export PATH="$root/tests/fake-bin:$PATH"
  unset FAKE_BT_NONE FAKE_SCQ_DELAY SOUNDCORE_CALL_TIMEOUT SOUNDCORE_LOCK_TIMEOUT
}

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
    and ([.schema[].categoryId] == ["soundModes", "equalizer"])
    and .values.ambientSoundMode == "Normal"
    and .values.volumeAdjustments == [0,0,0,0,0,0,0,0]
    and .values.batteryLevel == "4/5"
    and (.values | has("firmwareVersion") | not)
  ' <<<"$out" >/dev/null
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
  "$root/soundcore-set" "$mac" ambientSoundMode=NoiseCanceling noiseCancelingMode=Transport \
    volumeAdjustments=10,-20,0,0,0,0,0,5 presetEqualizerProfile= >/dev/null || return 1
  [ "$(device_calls)" = 1 ] &&
    [ "$(value ambientSoundMode)" = NoiseCanceling ] &&
    [ "$(value noiseCancelingMode)" = Transport ] &&
    [ "$(value volumeAdjustments)" = "10,-20,0,0,0,0,0,5" ] &&
    [ "$(value presetEqualizerProfile)" = null ]
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
  local rc=0
  "$root/soundcore-set" "$mac" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ]
}

check "no connected device reports disconnected" t_no_device
check "full status reads schema, values and battery" t_full_status
check "--quick finds the device without connecting to it" t_quick_status_does_not_connect
check "status reports a failed device read as an error" t_status_reports_device_errors
check "set waits for an in-flight status read instead of failing" t_set_during_status
check "status waits for an in-flight set and sees its result" t_status_during_set
check "--quick does not wait on the device lock" t_quick_status_does_not_wait_for_lock
check "set applies several settings over one connection" t_set_applies_several_settings_in_one_connection
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
