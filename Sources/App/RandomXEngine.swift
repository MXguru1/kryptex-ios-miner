import Foundation

enum RandomXError: Error {
    case contextFailed
    case seedRejected(Int32)
}

/// Swift wrapper over the RandomX light-mode bridge (Sources/RandomX/rx_bridge.h).
/// Not thread-safe: use one instance from one thread at a time.
final class RandomXEngine {
    private let ctx: OpaquePointer

    init() throws {
        guard let created = rx_create() else {
            throw RandomXError.contextFailed
        }
        ctx = created
    }

    deinit {
        rx_destroy(ctx)
    }

    /// Loads the RandomX cache for `seed`. Takes a while when the seed changes.
    func setSeed(_ seed: Data) throws {
        let rc = seed.withUnsafeBytes { raw in
            rx_set_seed(ctx, raw.bindMemory(to: UInt8.self).baseAddress, seed.count)
        }
        guard rc == 0 else {
            throw RandomXError.seedRejected(rc)
        }
    }

    /// Hashes `input` with the loaded seed. Returns 32 bytes.
    func hash(_ input: Data) -> Data {
        var output = Data(count: 32)
        output.withUnsafeMutableBytes { outRaw in
            input.withUnsafeBytes { inRaw in
                rx_hash(ctx,
                        inRaw.bindMemory(to: UInt8.self).baseAddress,
                        input.count,
                        outRaw.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return output
    }
}
