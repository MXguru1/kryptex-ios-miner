#include "rx_bridge.h"

#include "randomx.h"

#include <cstring>
#include <vector>

// RandomX's arm64 JIT calls __builtin___clear_cache(), which clang lowers to a call to
// __clear_cache(). Apple's runtime does not export that symbol, so the link fails with
// "Undefined symbols for architecture arm64: ___clear_cache". Apple's equivalent is
// sys_icache_invalidate().
//
// Defining it here instead of editing ThirdParty/RandomX keeps the vendored tree
// byte-identical to its pinned upstream commit. The interpreter never executes
// JIT-emitted code (kFlags below is RANDOMX_FLAG_DEFAULT), but jit_compiler_a64.o is
// still linked into the target, so the symbol has to resolve.
#if defined(__APPLE__) && defined(__aarch64__)
#include <libkern/OSCacheControl.h>

extern "C" void __clear_cache(void *start, void *end) {
    const auto bytes =
        static_cast<size_t>(static_cast<char *>(end) - static_cast<char *>(start));
    sys_icache_invalidate(start, bytes);
}
#endif

struct rx_ctx {
    randomx_cache *cache = nullptr;
    randomx_vm *vm = nullptr;
    std::vector<uint8_t> seed;
};

// RANDOMX_FLAG_DEFAULT means interpreter, light mode (256 MiB cache, no dataset).
// iOS does not allow the JIT for sideloaded apps, so this path is intentional.
static const randomx_flags kFlags = RANDOMX_FLAG_DEFAULT;

rx_ctx *rx_create(void) {
    return new rx_ctx();
}

int rx_set_seed(rx_ctx *ctx, const uint8_t *seed, size_t seed_len) {
    if (!ctx || !seed || seed_len == 0) {
        return -1;
    }
    if (ctx->vm && ctx->seed.size() == seed_len &&
        std::memcmp(ctx->seed.data(), seed, seed_len) == 0) {
        return 0;
    }

    if (!ctx->cache) {
        ctx->cache = randomx_alloc_cache(kFlags);
        if (!ctx->cache) {
            return -2;
        }
    }
    randomx_init_cache(ctx->cache, seed, seed_len);

    if (!ctx->vm) {
        ctx->vm = randomx_create_vm(kFlags, ctx->cache, nullptr);
        if (!ctx->vm) {
            return -3;
        }
    } else {
        randomx_vm_set_cache(ctx->vm, ctx->cache);
    }

    ctx->seed.assign(seed, seed + seed_len);
    return 0;
}

void rx_hash(rx_ctx *ctx, const uint8_t *input, size_t input_len, uint8_t out[32]) {
    randomx_calculate_hash(ctx->vm, input, input_len, out);
}

void rx_destroy(rx_ctx *ctx) {
    if (!ctx) {
        return;
    }
    // The VM references the cache, so it must be destroyed first.
    if (ctx->vm) {
        randomx_destroy_vm(ctx->vm);
    }
    if (ctx->cache) {
        randomx_release_cache(ctx->cache);
    }
    delete ctx;
}
