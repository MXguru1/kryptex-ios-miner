#!/usr/bin/env bash
# Single-thread RandomX light-mode hashrate on this Linux host (interpreter, no JIT).
# Run from the repo root with Docker:
#   docker run --rm -v "$PWD:/work:ro" swift:6.0 bash /work/tests/linux/bench.sh [hashes]
set -euo pipefail

SRC=/work
OUT=/tmp/rxbench
RX="$SRC/ThirdParty/RandomX/src"
rm -rf "$OUT"
mkdir -p "$OUT"

OPT=-O3 source "$SRC/tests/linux/build_randomx.sh"

clang++ -std=c++14 -O3 -DNDEBUG -I"$RX" -I"$SRC/Sources/RandomX" \
  "$SRC/tests/linux/bench.cpp" "${OBJS[@]}" -lstdc++ -lpthread -o "$OUT/bench"
"$OUT/bench" "${1:-500}"
