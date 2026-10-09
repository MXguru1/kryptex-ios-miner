// Test-only stand-in for Sources/App/StratumClient.swift. The real file imports
// Network.framework, which does not exist on Linux. This mirrors only the Job
// type that MiningWorker depends on.
enum StratumClient {
    struct Job: Equatable {
        let jobId: String
        let blob: String
        let target: String
        let height: Int
        let seedHash: String
    }
}
