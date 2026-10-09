// Single-thread RandomX light-mode benchmark through rx_bridge.
// Reports cache init time and sustained hashes per second. The numbers describe the
// host it runs on (interpreter, light mode), not an iPhone.
#include "rx_bridge.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char **argv) {
    const int hashes = argc > 1 ? std::atoi(argv[1]) : 500;
    const char *key = "benchmark seed";

    rx_ctx *ctx = rx_create();
    auto t0 = std::chrono::steady_clock::now();
    if (rx_set_seed(ctx, reinterpret_cast<const uint8_t *>(key), std::strlen(key)) != 0) {
        std::printf("seed failed\n");
        rx_destroy(ctx);
        return 1;
    }
    auto t1 = std::chrono::steady_clock::now();

    uint8_t input[76];
    uint8_t out[32];
    for (int i = 0; i < 76; ++i) {
        input[i] = static_cast<uint8_t>(i);
    }
    for (int i = 0; i < 20; ++i) {  // warm-up
        rx_hash(ctx, input, sizeof input, out);
    }

    auto s = std::chrono::steady_clock::now();
    for (int i = 0; i < hashes; ++i) {
        input[39] = static_cast<uint8_t>(i);
        input[40] = static_cast<uint8_t>(i >> 8);
        rx_hash(ctx, input, sizeof input, out);
    }
    auto e = std::chrono::steady_clock::now();

    double initS = std::chrono::duration<double>(t1 - t0).count();
    double hashS = std::chrono::duration<double>(e - s).count();
    std::printf("cache init: %.2f s\n", initS);
    std::printf("hashes: %d, time: %.2f s, rate: %.2f H/s (1 thread, light mode, interpreter)\n",
                hashes, hashS, hashes / hashS);
    rx_destroy(ctx);
    return 0;
}
