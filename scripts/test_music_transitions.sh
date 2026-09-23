#!/usr/bin/env bash
set -euo pipefail

# Supply a booted iPhone simulator ID. The virtual watch exercises the same
# coordinator messages without depending on simulator WatchConnectivity.
PANCAKE_TEST_DEVICE="${1:?Pass a booted iPhone simulator ID}"
PANCAKE_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANCAKE_TEST_DERIVED="${PANCAKE_SIM_DERIVED_DATA:-$PANCAKE_TEST_ROOT/.derivedData/MusicTransitions}"
PANCAKE_TEST_LOGS="$(mktemp -d "${TMPDIR:-/tmp}/pancake-music-transitions.XXXXXX")"
PANCAKE_TEST_BUNDLE="com.Matthew-Lucas.Hello-World.Pancake"

xcodebuild -scheme Pancake -project "$PANCAKE_TEST_ROOT/Pancake.xcodeproj" \
  -configuration Debug -destination "id=$PANCAKE_TEST_DEVICE" \
  -derivedDataPath "$PANCAKE_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO ENABLE_PREVIEWS=NO build \
  >"$PANCAKE_TEST_LOGS/build.log" 2>&1
xcrun simctl install "$PANCAKE_TEST_DEVICE" "$PANCAKE_TEST_DERIVED/Build/Products/Debug-iphonesimulator/Pancake.app"
PANCAKE_TEST_DATA="$(xcrun simctl get_app_container "$PANCAKE_TEST_DEVICE" "$PANCAKE_TEST_BUNDLE" data)"

for PANCAKE_TEST_PAUSED in 0 1; do
  rm -f "$PANCAKE_TEST_DATA/Documents/pancake-sim.log"
  SIMCTL_CHILD_PANCAKE_SIMULATED_RUN=1 \
  SIMCTL_CHILD_PANCAKE_SIMULATED_MUSIC=1 \
  SIMCTL_CHILD_PANCAKE_SIM_TRANSITION_TEST=1 \
  SIMCTL_CHILD_PANCAKE_SIM_LOCAL_TRANSITION_TEST=1 \
  SIMCTL_CHILD_PANCAKE_SIM_PAUSED_TRANSITION_TEST="$PANCAKE_TEST_PAUSED" \
    xcrun simctl launch --terminate-running-process "$PANCAKE_TEST_DEVICE" "$PANCAKE_TEST_BUNDLE" >/dev/null

  for _ in {1..90}; do
    if rg -q 'PANCAKE_SIM:LOCAL_TRANSITION_COMPLETE' "$PANCAKE_TEST_DATA/Documents/pancake-sim.log" 2>/dev/null; then break; fi
    sleep 0.5
  done
  cp "$PANCAKE_TEST_DATA/Documents/pancake-sim.log" "$PANCAKE_TEST_LOGS/paused-$PANCAKE_TEST_PAUSED.log"
  python3 - "$PANCAKE_TEST_LOGS/paused-$PANCAKE_TEST_PAUSED.log" "$PANCAKE_TEST_PAUSED" <<'PY'
import re
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text()
paused = sys.argv[2] == '1'
assert 'PANCAKE_SIM:LOCAL_TRANSITION_COMPLETE' in log, 'Scenario did not finish'
played = re.findall(r'PANCAKE_SIM:PLAYED key=(.*?) title=', log)
transitions = [(int(i), float(t)) for i, t in re.findall(r'PANCAKE_SIM:TRANSITION target=(\d+) time=([\d.]+)', log)]
peak = [time for index, time in transitions if index == 1]
expected = 65 if paused else 48
assert len(peak) == 1 and abs(peak[0] - expected) <= 1, f'Unexpected transitions: {transitions}'
assert len(played) == 4 and len(set(played)) == 4, f'Expected four distinct played songs: {played}'
assert 'calm' in played[0], f'Initial song did not fit Zone 1: {played}'
assert all('explosive' in key for key in played[1:]), f'Wrong-zone track on transition or skip: {played}'
if paused:
    assert 'PANCAKE_SIM:PAUSE_PRESERVED=true' in log, 'Transition resumed paused playback'
print(f"Music transition scenario passed (paused={paused}, transition={peak[0]}s, four suitable songs).")
PY
done
echo "Logs: $PANCAKE_TEST_LOGS"
