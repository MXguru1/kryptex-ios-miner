// Known-answer test for rx_bridge against the upstream RandomX test vectors
// (src/tests/tests.cpp in tevador/RandomX v1.2.1). Build it with the bridge
// sources and a RandomX static library (see the README).
#include "rx_bridge.h"

#include <cstdio>
#include <cstring>
#include <string>

static std::string toHex(const uint8_t *data, size_t len) {
    static const char digits[] = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < len; ++i) {
        s.push_back(digits[data[i] >> 4]);
        s.push_back(digits[data[i] & 0x0f]);
    }
    return s;
}

static int failures = 0;

static void check(rx_ctx *ctx, const char *key, const char *input, const char *expectedHex) {
    if (rx_set_seed(ctx, reinterpret_cast<const uint8_t *>(key), std::strlen(key)) != 0) {
        std::printf("FAIL set_seed for key '%s'\n", key);
        ++failures;
        return;
    }
    uint8_t out[32];
    rx_hash(ctx, reinterpret_cast<const uint8_t *>(input), std::strlen(input), out);
    std::string got = toHex(out, sizeof out);
    if (got == expectedHex) {
        std::printf("PASS key='%s' input='%s'\n", key, input);
    } else {
        std::printf("FAIL key='%s' input='%s'\n  got  %s\n  want %s\n", key, input, got.c_str(), expectedHex);
        ++failures;
    }
}

int main() {
    rx_ctx *ctx = rx_create();

    check(ctx, "test key 000", "This is a test",
          "639183aae1bf4c9a35884cb46b09cad9175f04efd7684e7262a0ac1c2f0b4e3f");
    check(ctx, "test key 000", "Lorem ipsum dolor sit amet",
          "300a0adb47603dedb42228ccb2b211104f4da45af709cd7547cd049e9489c969");
    // Switching the seed must reload the cache and produce the other key's hash.
    check(ctx, "test key 001", "sed do eiusmod tempor incididunt ut labore et dolore magna aliqua",
          "e9ff4503201c0c2cca26d285c93ae883f9b1d30c9eb240b820756f2d5a7905fc");
    check(ctx, "test key 000", "sed do eiusmod tempor incididunt ut labore et dolore magna aliqua",
          "c36d4ed4191e617309867ed66a443be4075014e2b061bcdaf9ce7b721d2b77a8");

    rx_destroy(ctx);
    std::printf("%s (%d failure(s))\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
    return failures == 0 ? 0 : 1;
}
