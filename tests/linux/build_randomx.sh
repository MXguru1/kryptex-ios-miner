# Sourced, not executed. Expects SRC (repo root) and OUT (scratch dir) to be set.
# Builds RandomX and the C bridge into $OUT/obj and sets OBJS to their paths.
# OPT sets the optimization level (default -O2).
#
# The RandomX file list is read from project.yml, the same list the iOS target uses.

OPT="${OPT:--O2}"
RX="$SRC/ThirdParty/RandomX/src"
mkdir -p "$OUT/obj"

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
echo "RandomX source files built here: ${#RX_FILES[@]} (host $(uname -m), $OPT)"

OBJS=()
for rel in "${RX_FILES[@]}"; do
  f="$SRC/$rel"
  o="$OUT/obj/$(echo "$rel" | tr '/' '_').o"
  case "$f" in
    *.c)   clang "$OPT" -I"$RX" -c "$f" -o "$o" ;;
    *.cpp) clang++ -std=c++14 "$OPT" -I"$RX" -c "$f" -o "$o" ;;
    *.S)   clang -c "$f" -o "$o" ;;
  esac
  OBJS+=("$o")
done

clang++ -std=c++14 "$OPT" -I"$RX" -I"$SRC/Sources/RandomX" \
  -c "$SRC/Sources/RandomX/rx_bridge.cpp" -o "$OUT/obj/rx_bridge.o"
OBJS+=("$OUT/obj/rx_bridge.o")
