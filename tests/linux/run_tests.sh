#!/usr/bin/env bash
# Builds the vendored RandomX sources (file list read from project.yml), the C bridge,
# and the Swift hashing code on Linux, then runs the C and Swift checks.
#
# Run from the repo root with Docker:
#   docker run --rm -v "$PWD:/work:ro" swift:6.0 bash /work/tests/linux/run_tests.sh
#
# This is a Linux check. It does not build the iOS target, UIKit/SwiftUI code,
# or StratumClient (Network.framework). See README for what remains unverified.
set -euo pipefail

SRC=/work
OUT=/tmp/rxtest
RX="$SRC/ThirdParty/RandomX/src"
rm -rf "$OUT"
mkdir -p "$OUT"

source "$SRC/tests/linux/build_randomx.sh"

echo "== C bridge known-answer test"
clang++ -std=c++14 -O2 -I"$RX" -I"$SRC/Sources/RandomX" \
  "$SRC/tests/bridge_test.cpp" "${OBJS[@]}" -lstdc++ -lpthread -o "$OUT/bridge_test"
"$OUT/bridge_test"

echo "== Swift wrapper and worker checks"
swiftc -O \
  -Xcc -I"$SRC/Sources/RandomX" -Xcc -I"$RX" \
  -import-objc-header "$SRC/Sources/App/KryptexMiner-Bridging-Header.h" \
  "$SRC/Sources/App/RandomXEngine.swift" \
  "$SRC/Sources/App/MiningWorker.swift" \
  "$SRC/tests/linux/StratumJobShim.swift" \
  "$SRC/tests/linux/main.swift" \
  "${OBJS[@]}" -lstdc++ -o "$OUT/worker_test"
"$OUT/worker_test"

echo "ALL LINUX CHECKS PASSED"
