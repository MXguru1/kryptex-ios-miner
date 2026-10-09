#ifndef RX_BRIDGE_H
#define RX_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rx_ctx rx_ctx;

/// Creates an empty context. No seed is loaded until rx_set_seed is called.
rx_ctx *rx_create(void);

/// Loads (or reloads) the RandomX cache for `seed`. Returns 0 on success.
/// If the seed is unchanged from the previous call, this is a no-op.
int rx_set_seed(rx_ctx *ctx, const uint8_t *seed, size_t seed_len);

/// Hashes `input` with the currently loaded seed. Writes 32 bytes to `out`.
/// rx_set_seed must have succeeded first.
void rx_hash(rx_ctx *ctx, const uint8_t *input, size_t input_len, uint8_t out[32]);

/// Frees all resources held by `ctx`. Safe to pass NULL.
void rx_destroy(rx_ctx *ctx);

#ifdef __cplusplus
}
#endif

#endif /* RX_BRIDGE_H */
