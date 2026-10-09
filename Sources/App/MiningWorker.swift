import Foundation

/// Hashes RandomX on one background thread and reports shares that meet the job target.
/// The engine is created and used only on that thread. The UI thread passes in work
/// through `setWork`, which is guarded by a lock.
final class MiningWorker {
    struct Work {
        let jobId: String
        let seed: Data
        let blob: Data
        let target: UInt64
    }

    /// Called on the worker thread: jobId, nonce hex (as in the blob), result hash hex.
    var onShare: ((String, String, String) -> Void)?
    /// Called on the worker thread about once per second.
    var onHashrate: ((Double) -> Void)?
    /// Called on the worker thread when the engine cannot run.
    var onError: ((String) -> Void)?

    private let lock = NSLock()
    private var work: Work?
    private var running = false
    private var thread: Thread?

    func setWork(_ newWork: Work?) {
        lock.lock()
        work = newWork
        lock.unlock()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "randomx-worker"
        self.thread = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        running = false
        work = nil
        thread = nil
        lock.unlock()
    }

    // MARK: - Job parsing (static, usable from any thread)

    /// Builds worker input from a Stratum job. Returns nil if any field is malformed.
    static func makeWork(from job: StratumClient.Job) -> Work? {
        guard let blob = Data(hex: job.blob), blob.count >= 43,
              let seed = Data(hex: job.seedHash), !seed.isEmpty,
              let target = parseTarget(job.target) else {
            return nil
        }
        return Work(jobId: job.jobId, seed: seed, blob: blob, target: target)
    }

    /// Converts a Stratum target into the 64-bit threshold used by XMRig.
    /// 4-byte targets are a 32-bit difficulty form; 8-byte targets are used directly.
    static func parseTarget(_ hex: String) -> UInt64? {
        guard let bytes = Data(hex: hex) else { return nil }
        var value: UInt64 = 0
        switch bytes.count {
        case 4:
            for (i, byte) in bytes.enumerated() {
                value |= UInt64(byte) << (8 * UInt64(i))
            }
            guard value != 0 else { return nil }
            let difficulty = 0xFFFF_FFFF / value
            guard difficulty != 0 else { return nil }
            return UInt64.max / difficulty
        case 8:
            for (i, byte) in bytes.enumerated() {
                value |= UInt64(byte) << (8 * UInt64(i))
            }
            return value
        default:
            return nil
        }
    }

    /// A hash meets the target when its last 8 bytes, read little-endian, are below it.
    static func meetsTarget(_ digest: Data, target: UInt64) -> Bool {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(digest[digest.startIndex + 24 + i]) << (8 * UInt64(i))
        }
        return value < target
    }

    // MARK: - Worker loop

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func currentWork() -> Work? {
        lock.lock()
        defer { lock.unlock() }
        return work
    }

    private func run() {
        let engine: RandomXEngine
        do {
            engine = try RandomXEngine()
        } catch {
            onError?("RandomX context failed to start")
            return
        }

        var loadedSeed = Data()
        var jobId = ""
        var nonce: UInt32 = 0
        var hashes: UInt64 = 0
        var windowStart = Date()

        while isRunning {
            guard let current = currentWork() else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }

            if current.seed != loadedSeed {
                do {
                    try engine.setSeed(current.seed)
                    loadedSeed = current.seed
                } catch {
                    onError?("RandomX rejected the seed")
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
            }

            if current.jobId != jobId {
                jobId = current.jobId
                nonce = UInt32.random(in: 0...UInt32.max)
            }

            var blob = current.blob
            let nonceBytes = withUnsafeBytes(of: nonce.littleEndian) { Data($0) }
            blob.replaceSubrange(39..<43, with: nonceBytes)

            let digest = engine.hash(blob)
            hashes += 1
            if Self.meetsTarget(digest, target: current.target) {
                onShare?(current.jobId, nonceBytes.hexString, digest.hexString)
            }
            nonce &+= 1

            let elapsed = Date().timeIntervalSince(windowStart)
            if elapsed >= 1 {
                onHashrate?(Double(hashes) / elapsed)
                hashes = 0
                windowStart = Date()
            }
        }
        onHashrate?(0)
    }
}

extension Data {
    /// Parses a lowercase or uppercase hex string. Returns nil on odd length or non-hex input.
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
