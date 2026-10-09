import AVFoundation

/// Keeps the app running with the screen off by looping a silent audio buffer.
/// This relies on the `audio` background mode in Info.plist. It is not reviewed
/// by the App Store, so it is intended only for sideloaded builds.
final class SilentAudioKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    func start() throws {
        guard !running else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(domain: "SilentAudioKeepAlive", code: 1)
        }
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SilentAudioKeepAlive", code: 2)
        }
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            channel.update(repeating: 0, count: Int(frameCount))
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        running = true
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        running = false
    }
}
