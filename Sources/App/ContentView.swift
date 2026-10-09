import SwiftUI

struct ContentView: View {
    @StateObject private var miner = MinerController()

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("XMR wallet address", text: $miner.wallet)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("Worker name", text: $miner.workerName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Status") {
                    LabeledContent("State", value: miner.status)
                    LabeledContent("Connected", value: miner.isConnected ? "Yes" : "No")
                    LabeledContent("Last job", value: miner.lastJobId)
                }

                Section {
                    if miner.isRunning {
                        Button("Stop", role: .destructive) { miner.stop() }
                    } else {
                        Button("Start") { miner.start() }
                    }
                }

                Section("Log") {
                    ForEach(Array(miner.log.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Kryptex Miner")
        }
    }
}
