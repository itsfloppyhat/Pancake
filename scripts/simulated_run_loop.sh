#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Pancake.xcodeproj"
SCHEME="Pancake"
DERIVED_DATA="${PANCAKE_SIM_DERIVED_DATA:-$ROOT_DIR/.derivedData/PancakeSimLoop}"
LOG_DIR="${PANCAKE_SIM_LOG_DIR:-$ROOT_DIR/.simulator-logs/$(date +%Y%m%d-%H%M%S)}"

PHONE_NAME="${PANCAKE_SIM_PHONE_NAME:-Pancake iPhone Air}"
WATCH_NAME="${PANCAKE_SIM_WATCH_NAME:-Pancake Apple Watch Series 11}"
PHONE_DEVICE_TYPE="${PANCAKE_SIM_PHONE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-Air}"
WATCH_DEVICE_TYPE="${PANCAKE_SIM_WATCH_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm}"
PHONE_BUNDLE_ID="${PANCAKE_SIM_PHONE_BUNDLE_ID:-com.Matthew-Lucas.Hello-World.Pancake}"
WATCH_BUNDLE_ID="${PANCAKE_SIM_WATCH_BUNDLE_ID:-com.Matthew-Lucas.Hello-World.Pancake.watchkitapp}"
WAIT_SECONDS="${PANCAKE_SIM_WAIT_SECONDS:-145}"
SPEED_MPS="${PANCAKE_SIM_SPEED_MPS:-3.15}"

mkdir -p "$LOG_DIR"

pick_runtime() {
  local platform="$1"
  local device_type="$2"
  /usr/bin/python3 - "$platform" "$device_type" <<'PY'
import json
import subprocess
import sys

platform = sys.argv[1]
device_type = sys.argv[2]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))

def version_key(runtime):
    return tuple(int(part) for part in runtime.get("version", "0").split(".") if part.isdigit())

runtimes = [
    runtime for runtime in data.get("runtimes", [])
    if runtime.get("isAvailable")
    and runtime.get("platform") == platform
    and any(device.get("identifier") == device_type for device in runtime.get("supportedDeviceTypes", []))
]

if not runtimes:
    raise SystemExit(f"No available {platform} runtime supports {device_type}")

print(max(runtimes, key=version_key)["identifier"])
PY
}

device_udid_by_name() {
  local name="$1"
  /usr/bin/python3 - "$name" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"]))
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(1)
PY
}

pair_id_for_devices() {
  local watch_udid="$1"
  local phone_udid="$2"
  /usr/bin/python3 - "$watch_udid" "$phone_udid" <<'PY'
import json
import subprocess
import sys

watch_udid = sys.argv[1]
phone_udid = sys.argv[2]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "pairs", "-j"]))
for pair_id, pair in data.get("pairs", {}).items():
    watch = pair.get("watch", {})
    phone = pair.get("phone", {})
    if watch.get("udid") == watch_udid and phone.get("udid") == phone_udid:
        print(pair_id)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ensure_device() {
  local name="$1"
  local device_type="$2"
  local runtime="$3"
  local udid

  if udid="$(device_udid_by_name "$name")"; then
    printf '%s\n' "$udid"
    return
  fi

  xcrun simctl create "$name" "$device_type" "$runtime"
}

wait_for_file() {
  local path="$1"
  local label="$2"

  for _ in {1..120}; do
    if [[ -e "$path" ]]; then
      return
    fi
    sleep 1
  done

  echo "Timed out waiting for $label at $path" >&2
  exit 1
}

IOS_RUNTIME="${PANCAKE_SIM_IOS_RUNTIME:-$(pick_runtime iOS "$PHONE_DEVICE_TYPE")}"
WATCH_RUNTIME="${PANCAKE_SIM_WATCH_RUNTIME:-$(pick_runtime watchOS "$WATCH_DEVICE_TYPE")}"

PHONE_UDID="$(ensure_device "$PHONE_NAME" "$PHONE_DEVICE_TYPE" "$IOS_RUNTIME")"
WATCH_UDID="$(ensure_device "$WATCH_NAME" "$WATCH_DEVICE_TYPE" "$WATCH_RUNTIME")"

if ! PAIR_ID="$(pair_id_for_devices "$WATCH_UDID" "$PHONE_UDID")"; then
  xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID" >/dev/null
  sleep 2
  PAIR_ID="$(pair_id_for_devices "$WATCH_UDID" "$PHONE_UDID")"
fi

xcrun simctl pair_activate "$PAIR_ID" >/dev/null 2>&1 || true
xcrun simctl boot "$PHONE_UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$WATCH_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$PHONE_UDID" -b >/dev/null
xcrun simctl bootstatus "$WATCH_UDID" -b >/dev/null

open -a Simulator --args -CurrentDeviceUDID "$PHONE_UDID" >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$WATCH_UDID" >/dev/null 2>&1 || true

echo "Building Pancake for paired simulators..."
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
  -scheme "$SCHEME" \
  -project "$PROJECT_PATH" \
  -configuration Debug \
  -destination "id=$PHONE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_PREVIEWS=NO \
  build \
  >"$LOG_DIR/xcodebuild.log" 2>&1

PHONE_APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Pancake.app"
WATCH_APP="$DERIVED_DATA/Build/Products/Debug-watchsimulator/Pancake Watch Watch App.app"
wait_for_file "$PHONE_APP" "iPhone app"
wait_for_file "$WATCH_APP" "watch app"

xcrun simctl install "$PHONE_UDID" "$PHONE_APP"
xcrun simctl install "$WATCH_UDID" "$WATCH_APP"

PHONE_CONTAINER="$(xcrun simctl get_app_container "$PHONE_UDID" "$PHONE_BUNDLE_ID" data)"
WATCH_CONTAINER="$(xcrun simctl get_app_container "$WATCH_UDID" "$WATCH_BUNDLE_ID" data)"
rm -f "$PHONE_CONTAINER/Documents/pancake-sim.log" "$WATCH_CONTAINER/Documents/pancake-sim.log"

xcrun simctl privacy "$WATCH_UDID" grant location "$WATCH_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$WATCH_UDID" grant motion "$WATCH_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$PHONE_UDID" grant media-library "$PHONE_BUNDLE_ID" >/dev/null 2>&1 || true

cleanup() {
  xcrun simctl location "$WATCH_UDID" clear >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl location "$WATCH_UDID" start \
  --speed="$SPEED_MPS" \
  --interval=1 \
  40.78478,-73.96536 \
  40.78290,-73.95890 \
  40.77730,-73.96040 \
  40.77520,-73.96680 \
  40.77980,-73.97120 \
  40.78478,-73.96536

echo "Launching watch and iPhone apps..."
SIMCTL_CHILD_PANCAKE_SIMULATED_RUN=1 \
SIMCTL_CHILD_PANCAKE_SIMULATED_MUSIC=1 \
SIMCTL_CHILD_PANCAKE_SIMULATED_SPEED_MPS="$SPEED_MPS" \
xcrun simctl launch \
  --terminate-running-process \
  --stdout="$LOG_DIR/watch.stdout.log" \
  --stderr="$LOG_DIR/watch.stderr.log" \
  "$WATCH_UDID" \
  "$WATCH_BUNDLE_ID" \
  --pancake-simulated-run \
  --pancake-simulated-music \
  >/dev/null

sleep 2

SIMCTL_CHILD_PANCAKE_SIMULATED_RUN=1 \
SIMCTL_CHILD_PANCAKE_SIMULATED_MUSIC=1 \
xcrun simctl launch \
  --terminate-running-process \
  --stdout="$LOG_DIR/iphone.stdout.log" \
  --stderr="$LOG_DIR/iphone.stderr.log" \
  "$PHONE_UDID" \
  "$PHONE_BUNDLE_ID" \
  --pancake-simulated-run \
  --pancake-simulated-music \
  >/dev/null

echo "Running simulated workout for ${WAIT_SECONDS}s..."
sleep "$WAIT_SECONDS"
sleep 2

cp "$PHONE_CONTAINER/Documents/pancake-sim.log" "$LOG_DIR/iphone.file.log" 2>/dev/null || true
cp "$WATCH_CONTAINER/Documents/pancake-sim.log" "$LOG_DIR/watch.file.log" 2>/dev/null || true

COMBINED_LOG="$LOG_DIR/combined.log"
: >"$COMBINED_LOG"
if [[ -s "$LOG_DIR/iphone.file.log" ]]; then
  cat "$LOG_DIR/iphone.file.log" >>"$COMBINED_LOG"
else
  cat "$LOG_DIR/iphone.stdout.log" "$LOG_DIR/iphone.stderr.log" >>"$COMBINED_LOG" 2>/dev/null || true
fi

if [[ -s "$LOG_DIR/watch.file.log" ]]; then
  cat "$LOG_DIR/watch.file.log" >>"$COMBINED_LOG"
else
  cat "$LOG_DIR/watch.stdout.log" "$LOG_DIR/watch.stderr.log" >>"$COMBINED_LOG" 2>/dev/null || true
fi

/usr/bin/python3 - "$COMBINED_LOG" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
lines = log_path.read_text(errors="replace").splitlines()
played = []
played_set = set()
queues = []
errors = []

for line in lines:
    if "PANCAKE_SIM:PLAYED" in line:
        match = re.search(r"key=(.*?) title=", line)
        if not match:
            errors.append(f"Malformed played-song log: {line}")
            continue
        key = match.group(1)
        if key in played_set:
            errors.append(f"Played song repeated: {key}")
        played.append(key)
        played_set.add(key)

    if "PANCAKE_SIM:QUEUE" in line:
        match = re.search(r"revision=(\d+).*songs=(.*?) played=", line)
        if not match:
            errors.append(f"Malformed queue log: {line}")
            continue
        revision = int(match.group(1))
        songs = [song for song in match.group(2).split(",") if song]
        queues.append((revision, songs))
        if len(songs) != 3:
            errors.append(f"Queue revision {revision} had {len(songs)} songs, expected 3")
        if len(songs) != len(set(songs)):
            errors.append(f"Queue revision {revision} contained a duplicate song")
        repeated_played = sorted(set(songs) & played_set)
        if repeated_played:
            errors.append(f"Queue revision {revision} requeued already played song(s): {', '.join(repeated_played)}")

if len(queues) < 2:
    errors.append(f"Expected at least 2 playlist generations, saw {len(queues)}")

if len(played) < 2:
    errors.append(f"Expected at least 2 played songs after skip/natural advance, saw {len(played)}")

required_markers = [
    "PANCAKE_SIM: Watch requested Adaptive Mix",
    "PANCAKE_SIM: Watch requested next song",
    "PANCAKE_SIM: Watch simulated workout completed",
    "PANCAKE_SIM:SAVE_RUN_EVENT",
]
for marker in required_markers:
    if not any(marker in line for line in lines):
        errors.append(f"Missing marker: {marker}")

if errors:
    print("Pancake simulator loop failed:")
    for error in errors:
        print(f"- {error}")
    print(f"Logs: {log_path}")
    raise SystemExit(1)

print("Pancake simulator loop passed.")
print(f"Playlist revisions: {len(queues)}")
print(f"Played songs: {len(played)}")
print(f"Logs: {log_path}")
PY
