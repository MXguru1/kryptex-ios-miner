import Foundation

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
    @Published private(set) var log: [String] = []

    private let keepAlive = SilentAudioKeepAlive()
    private let engine = RandomXEngine()
    private lazy var client = StratumClient { [weak self] event in
        self?.handle(event)
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
        status = engine.isLinked ? "Connecting…" : "Connecting (RandomX not linked: no hashing)"
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
        client.stop()
        keepAlive.stop()
        isRunning = false
        isConnected = false
        status = "Stopped"
        append("Stopped")
    }

    private func handle(_ event: StratumClient.Event) {
        switch event {
        case .connected:
            append("TCP connected, logging in")
        case .loggedIn(let sessionId):
            isConnected = true
            status = engine.isLinked ? "Mining" : "Logged in (RandomX not linked: no hashing)"
            append("Logged in, session \(sessionId)")
        case .job(let job):
            lastJobId = job.jobId
            append("Job \(job.jobId) height \(job.height)")
            // TODO: hand the job to the RandomX engine once it is linked.
        case .submitResult(let accepted, let message):
            append(accepted ? "Share accepted" : "Share rejected: \(message ?? "unknown")")
        case .failed(let message):
            isConnected = false
            status = "Error: \(message)"
            append("Error: \(message)")
            if isRunning {
                stop()
            }
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 200 {
            log.removeFirst(log.count - 200)
        }
    }
}
