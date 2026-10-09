#!/usr/bin/env bash
# Builds the vendored RandomX sources (file list read from project.yml), the C bridge,
# and the Swift hashing code on Linux, then runs the C and Swift checks.
#
# Run from the repo root with Docker:
#   docker run --rm -v "$PWD:/work:ro" swift:6.0 bash /work/tests/linux/run_tests.sh
#
# This is a Linux x86_64 check. It does not build the iOS target, UIKit/SwiftUI code,
# or StratumClient (Network.framework). See README for what remains unverified.
set -euo pipefail

SRC=/work
OUT=/tmp/rxtest
RX="$SRC/ThirdParty/RandomX/src"
rm -rf "$OUT"
mkdir -p "$OUT/obj"

# Single source of truth: the RandomX C/C++ files listed in project.yml.
mapfile -t RX_FILES < <(grep -oE 'ThirdParty/RandomX/src/[^ ]+\.(c|cpp)$' "$SRC/project.yml" | sort -u)
# The JIT is chosen by the host CPU (common.hpp). project.yml lists the arm64 JIT,
# which is what the iOS build uses. On an x86_64 host, swap in the x86 JIT pair so
# this check links, as upstream CMake does for x86_64.
if [[ "$(uname -m)" != "aarch64" ]]; then
  FILTERED=()
  for rel in "${RX_FILES[@]}"; do
    case "$rel" in *a64*) ;; *) FILTERED+=("$rel") ;; esac
  done
  FILTERED+=("ThirdParty/RandomX/src/jit_compiler_x86.cpp" "ThirdParty/RandomX/src/jit_compiler_x86_static.S")
  RX_FILES=("${FILTERED[@]}")
fi
echo "RandomX source files built here: ${#RX_FILES[@]}"

OBJS=()
for rel in "${RX_FILES[@]}"; do
  f="$SRC/$rel"
  o="$OUT/obj/$(echo "$rel" | tr '/' '_').o"
  case "$f" in
    *.c)   clang -O2 -I"$RX" -c "$f" -o "$o" ;;
    *.cpp) clang++ -std=c++14 -O2 -I"$RX" -c "$f" -o "$o" ;;
    *.S)   clang -c "$f" -o "$o" ;;
  esac
  OBJS+=("$o")
done

clang++ -std=c++14 -O2 -I"$RX" -I"$SRC/Sources/RandomX" \
  -c "$SRC/Sources/RandomX/rx_bridge.cpp" -o "$OUT/obj/rx_bridge.o"
OBJS+=("$OUT/obj/rx_bridge.o")

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
