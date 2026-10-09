import Foundation

// Swift-side checks for RandomXEngine, MiningWorker, and job parsing.
// Run through tests/linux/run_tests.sh. Exits non-zero on any failure.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("PASS \(name)")
    } else {
        print("FAIL \(name)")
        failures += 1
    }
}

// 1. RandomX known answers (upstream tests/tests.cpp, v1.2.1), through the Swift wrapper.
do {
    let engine = try RandomXEngine()
    let vectors: [(key: String, input: String, expected: String)] = [
        ("test key 000", "This is a test",
         "639183aae1bf4c9a35884cb46b09cad9175f04efd7684e7262a0ac1c2f0b4e3f"),
        ("test key 000", "Lorem ipsum dolor sit amet",
         "300a0adb47603dedb42228ccb2b211104f4da45af709cd7547cd049e9489c969"),
        ("test key 001", "sed do eiusmod tempor incididunt ut labore et dolore magna aliqua",
         "e9ff4503201c0c2cca26d285c93ae883f9b1d30c9eb240b820756f2d5a7905fc"),
    ]
    for v in vectors {
        try engine.setSeed(Data(v.key.utf8))
        let got = engine.hash(Data(v.input.utf8)).hexString
        check(got == v.expected, "engine vector key='\(v.key)' input='\(v.input)'")
    }
} catch {
    check(false, "engine setup failed: \(error)")
}

// 2. Target parsing.
check(MiningWorker.parseTarget("ffffff00") == UInt64.max / 256,
      "4-byte target ffffff00 -> difficulty 256")
check(MiningWorker.parseTarget("0100000000000000") == 1,
      "8-byte target is used directly")
check(MiningWorker.parseTarget("ffff") == nil, "short target rejected")
check(MiningWorker.parseTarget("00000000") == nil, "zero 4-byte target rejected")
check(MiningWorker.parseTarget("zz000000") == nil, "non-hex target rejected")

// 3. Job parsing guards.
let shortJob = StratumClient.Job(jobId: "j", blob: "00", target: "ffffff00",
                                 height: 1, seedHash: "00")
check(MiningWorker.makeWork(from: shortJob) == nil, "short blob rejected")

// 4. Target comparison uses the last 8 bytes, little-endian.
let highDigest = Data(repeating: 0xff, count: 32)
check(!MiningWorker.meetsTarget(highDigest, target: 1000), "all-ff digest misses target")
var lowDigest = Data(repeating: 0xff, count: 32)
for i in 24..<32 { lowDigest[i] = 0 }
check(MiningWorker.meetsTarget(lowDigest, target: 1), "zero tail meets target 1")

// 5. End-to-end worker run. Target UInt64.max accepts nearly every hash, so the
// worker reports shares quickly. Each reported share is recomputed independently.
let seed = Data("test key 000".utf8)
let blob = Data((0..<76).map { UInt8($0) })
let jobId = "job-1"
let work = MiningWorker.Work(jobId: jobId, seed: seed, blob: blob, target: UInt64.max)

let worker = MiningWorker()
let lock = NSLock()
var shares: [(job: String, nonce: String, result: String)] = []
let gotShare = DispatchSemaphore(value: 0)
worker.onShare = { job, nonce, result in
    lock.lock()
    shares.append((job, nonce, result))
    lock.unlock()
    gotShare.signal()
}
worker.setWork(work)
worker.start()
for _ in 0..<3 {
    _ = gotShare.wait(timeout: .now() + 120)
}
worker.stop()

lock.lock()
let captured = shares
lock.unlock()
check(captured.count >= 3, "worker reported >= 3 shares (got \(captured.count))")

do {
    let verifier = try RandomXEngine()
    try verifier.setSeed(seed)
    for share in captured.prefix(3) {
        guard let nonceBytes = Data(hex: share.nonce), nonceBytes.count == 4 else {
            check(false, "share nonce is 4 hex-encoded bytes")
            continue
        }
        var recomputed = blob
        recomputed.replaceSubrange(39..<43, with: nonceBytes)
        check(share.job == jobId, "share carries job id")
        check(verifier.hash(recomputed).hexString == share.result,
              "share nonce \(share.nonce) recomputes to reported hash")
    }
} catch {
    check(false, "verifier setup failed: \(error)")
}

print(failures == 0 ? "ALL SWIFT CHECKS PASSED" : "SWIFT CHECKS FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
