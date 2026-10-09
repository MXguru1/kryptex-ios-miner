/// Placeholder for the RandomX hashing engine.
///
/// Monero mining needs a RandomX library compiled for arm64 and linked into the
/// app (through a bridging header). Until that is done, `isLinked` is false: the
/// app still connects, logs in, and shows jobs, but it does not hash or submit shares.
struct RandomXEngine {
    var isLinked: Bool { false }
}
