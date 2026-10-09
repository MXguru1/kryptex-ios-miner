import Combine
import Foundation

/// One line of the in-app log. The monotonic `id` gives SwiftUI a stable
/// identity, so appending a line does not rebuild every row in the list.
struct LogEntry: Identifiable {
    let id: Int
    let text: String
}

@MainActor
final class MinerController: ObservableObject {
    /// Kryptex Monero (XMR) Europe endpoint, taken from the APK's MiningService
    /// (stratum+tcp://<coin>-<region>.kryptex.network:<port>).
    static let poolHost = "xmr-eu.kryptex.network"
    static let poolPort: UInt16 = 7029

    @Published var wallet: String = UserDefaults.standard.string(forKey: "wallet") ?? ""
    @Published var workerName: String = UserDefaults.standard.string(forKey: "worker") ?? "iphone"

    @Published private(set) var status = "Idle"
    @Published private(set) var isConnected = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastJobId = "-"
    @Published private(set) var hashrate: Double = 0
    @Published private(set) var accepted = 0
    @Published private(set) var rejected = 0
    @Published private(set) var log: [LogEntry] = []
    private var nextLogId = 0

    private let keepAlive = SilentAudioKeepAlive()
    private let worker = MiningWorker()
    private lazy var client = StratumClient { [weak self] event in
        Task { @MainActor in
            self?.handle(event)
        }
    }

    init() {
        worker.onShare = { [weak self] jobId, nonce, result in
            Task { @MainActor in
                self?.submitShare(jobId: jobId, nonce: nonce, result: result)
            }
        }
        worker.onHashrate = { [weak self] rate in
            Task { @MainActor in
                self?.hashrate = rate
            }
        }
        worker.onError = { [weak self] message in
            Task { @MainActor in
                self?.status = "Error: \(message)"
                self?.append("Error: \(message)")
            }
        }
    }

    func start() {
        let trimmed = wallet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Enter a wallet address first"
            return
        }
        UserDefaults.standard.set(trimmed, forKey: "wallet")
        UserDefaults.standard.set(workerName, forKey: "worker")

        do {
            try keepAlive.start()
        } catch {
            status = "Audio keep-alive failed: \(error.localizedDescription)"
            return
        }

        isRunning = true
        status = "Connecting…"
        worker.start()
        append("Connecting to \(Self.poolHost):\(Self.poolPort)")
        client.start(
            host: Self.poolHost,
            port: Self.poolPort,
            login: "\(trimmed)/\(workerName)",
            password: "x",
            agent: "KryptexIOS/1.0"
        )
    }

    func stop() {
        worker.stop()
        client.stop()
        keepAlive.stop()
        isRunning = false
        isConnected = false
        hashrate = 0
        status = "Stopped"
        append("Stopped")
    }

    private func handle(_ event: StratumClient.Event) {
        switch event {
        case .connected:
            append("TCP connected, logging in")
        case .loggedIn(let sessionId):
            isConnected = true
            status = "Logged in, waiting for job"
            append("Logged in, session \(sessionId)")
        case .job(let job):
            lastJobId = job.jobId
            append("Job \(job.jobId) height \(job.height)")
            if let work = MiningWorker.makeWork(from: job) {
                worker.setWork(work)
                status = "Mining"
            } else {
                append("Job rejected: malformed blob, target or seed_hash")
            }
        case .submitResult(let isAccepted, let message):
            if isAccepted {
                accepted += 1
                append("Share accepted (\(accepted))")
            } else {
                rejected += 1
                append("Share rejected: \(message ?? "unknown") (\(rejected))")
            }
        case .waiting(let message):
            // Transient. Keep the current job running and let the connection recover;
            // this is not a reason to stop mining.
            if isRunning {
                isConnected = false
                status = "Network unavailable, reconnecting…"
                append("Network unavailable: \(message), retrying")
            }
        case .failed(let message):
            isConnected = false
            status = "Error: \(message)"
            append("Error: \(message)")
            if isRunning {
                stop()
            }
        }
    }

    private func submitShare(jobId: String, nonce: String, result: String) {
        client.submit(jobId: jobId, nonce: nonce, result: result)
        append("Share found in job \(jobId), submitting")
    }

    private func append(_ line: String) {
        nextLogId += 1
        log.append(LogEntry(id: nextLogId, text: line))
        if log.count > 200 {
            log.removeFirst(log.count - 200)
        }
    }
}
