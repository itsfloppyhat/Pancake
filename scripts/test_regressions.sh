#!/usr/bin/env bash
set -euo pipefail

PANCAKE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANCAKE_TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/pancake-regressions.XXXXXX")"
trap 'rm -rf "$PANCAKE_TEST_BUILD"' EXIT

"$PANCAKE_ROOT/scripts/test_run_history_persistence.sh"

xcrun swiftc -parse-as-library \
  "$PANCAKE_ROOT/Pancake/Models/RunModels.swift" \
  "$PANCAKE_ROOT/Pancake/Models/MusicModels.swift" \
  "$PANCAKE_ROOT/Pancake/Models/UserProfileModels.swift" \
  "$PANCAKE_ROOT/Pancake/MusicRecommendationPolicy.swift" \
  "$PANCAKE_ROOT/Pancake/ActiveRunStateStore.swift" \
  "$PANCAKE_ROOT/Pancake/PlayedSongHistoryStore.swift" \
  "$PANCAKE_ROOT/Tests/MusicRecommendationPolicyRegression.swift" \
  -o "$PANCAKE_TEST_BUILD/music-regressions"
"$PANCAKE_TEST_BUILD/music-regressions"

xcrun swiftc -parse-as-library \
  "$PANCAKE_ROOT/Pancake Watch Watch App/RunModels.swift" \
  "$PANCAKE_ROOT/Pancake Watch Watch App/RunHistoryStore.swift" \
  "$PANCAKE_ROOT/Pancake Watch Watch App/WatchWorkoutState.swift" \
  "$PANCAKE_ROOT/Tests/WatchWorkoutStateRegression.swift" \
  -o "$PANCAKE_TEST_BUILD/watch-regressions"
"$PANCAKE_TEST_BUILD/watch-regressions"

xcrun swiftc -parse-as-library \
  "$PANCAKE_ROOT/Pancake/Models/SocialModels.swift" \
  "$PANCAKE_ROOT/Tests/CheerRunAlertPolicyRegression.swift" \
  -o "$PANCAKE_TEST_BUILD/cheer-regressions"
"$PANCAKE_TEST_BUILD/cheer-regressions"
