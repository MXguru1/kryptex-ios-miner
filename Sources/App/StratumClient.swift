import Foundation
import Network

/// Minimal Stratum client (newline-delimited JSON-RPC over TCP) for XMR pools.
/// All state is confined to `queue`; events are delivered on the main queue.
final class StratumClient {
    struct Job: Equatable {
        let jobId: String
        let blob: String
        let target: String
        let height: Int
        let seedHash: String
    }

    enum Event {
        case connected
        case loggedIn(sessionId: String)
        case job(Job)
        case submitResult(accepted: Bool, message: String?)
        /// The path went away but the connection is still usable: Network.framework
        /// holds on to it and resumes when a path appears. Distinct from `failed`,
        /// which means it has given up for good.
        case waiting(String)
        case failed(String)
    }

    private let queue = DispatchQueue(label: "kryptex.stratum")
    private let emit: (Event) -> Void

    private var connection: NWConnection?
    private var buffer = Data()
    private var nextId = 1
    private var loginId = 0
    private var sessionId: String?
    private var pendingSubmits = Set<Int>()

    init(emit: @escaping (Event) -> Void) {
        self.emit = emit
    }

    func start(host: String, port: UInt16, login: String, password: String, agent: String) {
        queue.async {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.report(.failed("Invalid port \(port)"))
                return
            }
            self.stopConnection()

            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            self.connection = conn
            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.queue.async {
                    switch state {
                    case .ready:
                        // A reconnect starts a fresh byte stream, so drop any partial
                        // line left from the previous one. It would otherwise be
                        // prefixed onto the first message parsed after recovery and
                        // break that whole line.
                        self.buffer = Data()
                        self.report(.connected)
                        self.loginId = self.allocateId()
                        self.send(id: self.loginId, method: "login", params: [
                            "login": login,
                            "pass": password,
                            "agent": agent,
                            "algo": ["rx/0"],
                        ])
                    case .failed(let error):
                        self.report(.failed(error.localizedDescription))
                    case .waiting(let error):
                        // Recoverable, not fatal. Reporting this as .failed made
                        // MinerController tear the session down on a brief blip,
                        // which also prevented the reconnect that the .ready
                        // branch above is written to handle.
                        self.report(.waiting(error.localizedDescription))
                    default:
                        break
                    }
                }
            }
            conn.start(queue: self.queue)
            self.receive(on: conn)
        }
    }

    func stop() {
        queue.async {
            self.stopConnection()
        }
    }

    func submit(jobId: String, nonce: String, result: String) {
        queue.async {
            guard let sessionId = self.sessionId else { return }
            let id = self.allocateId()
            self.pendingSubmits.insert(id)
            self.send(id: id, method: "submit", params: [
                "id": sessionId,
                "job_id": jobId,
                "nonce": nonce,
                "result": result,
            ])
        }
    }

    // MARK: - Private (queue-confined)

    private func stopConnection() {
        connection?.cancel()
        connection = nil
        buffer = Data()
        sessionId = nil
        pendingSubmits.removeAll()
    }

    private func allocateId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                // Ignore callbacks from a connection we already replaced or stopped.
                guard self.connection === conn else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drainLines()
                }
                if let error {
                    self.report(.failed(error.localizedDescription))
                    return
                }
                if isComplete {
                    self.report(.failed("Pool closed the connection"))
                    return
                }
                self.receive(on: conn)
            }
        }
    }

    private func drainLines() {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let method = message["method"] as? String, method == "job",
           let params = message["params"] as? [String: Any],
           let job = Job(json: params) {
            report(.job(job))
            return
        }

        guard let id = message["id"] as? Int else { return }

        if id == loginId {
            if let error = message["error"] as? [String: Any] {
                report(.failed(error["message"] as? String ?? "Login rejected"))
                return
            }
            guard let result = message["result"] as? [String: Any] else { return }
            sessionId = result["id"] as? String
            report(.loggedIn(sessionId: sessionId ?? ""))
            if let job = result["job"] as? [String: Any], let parsed = Job(json: job) {
                report(.job(parsed))
            }
            return
        }

        guard pendingSubmits.remove(id) != nil else { return }
        if let error = message["error"] as? [String: Any] {
            report(.submitResult(accepted: false, message: error["message"] as? String))
        } else {
            let status = (message["result"] as? [String: Any])?["status"] as? String
            report(.submitResult(accepted: status == "OK", message: nil))
        }
    }

    private func send(id: Int, method: String, params: [String: Any]) {
        let body: [String: Any] = [
            "id": id,
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: body) else { return }
        data.append(UInt8(ascii: "\n"))
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func report(_ event: Event) {
        DispatchQueue.main.async {
            self.emit(event)
        }
    }
}

extension StratumClient.Job {
    init?(json: [String: Any]) {
        guard let jobId = json["job_id"] as? String,
              let blob = json["blob"] as? String,
              let target = json["target"] as? String else {
            return nil
        }
        self.jobId = jobId
        self.blob = blob
        self.target = target
        self.height = json["height"] as? Int ?? 0
        self.seedHash = json["seed_hash"] as? String ?? ""
    }
}
