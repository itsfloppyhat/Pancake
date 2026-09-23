#!/usr/bin/env bash
set -euo pipefail

PANCAKE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANCAKE_TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/pancake-history-tests.XXXXXX")"
trap 'rm -rf "$PANCAKE_TEST_BUILD"' EXIT

xcrun swiftc -parse-as-library \
  "$PANCAKE_ROOT/Shared/DistanceUnit.swift" \
  "$PANCAKE_ROOT/Pancake/Models/RunModels.swift" \
  "$PANCAKE_ROOT/Pancake/ActiveRunStateStore.swift" \
  "$PANCAKE_ROOT/Pancake/RunHistoryRepository.swift" \
  "$PANCAKE_ROOT/Pancake/PendingRunCompletionStore.swift" \
  "$PANCAKE_ROOT/Tests/RunHistoryPersistenceRegression.swift" \
  -o "$PANCAKE_TEST_BUILD/run-history-regressions"

"$PANCAKE_TEST_BUILD/run-history-regressions"
