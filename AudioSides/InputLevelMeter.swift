import Accelerate
import AVFoundation
import Observation

/// A live level for the default input device, for the meter in the menu. The menu
/// starts it only while another app is already using the mic. It listens only between
/// `start()` and `stop()`, and never records or stores audio.
@Observable
final class InputLevelMeter {
    /// 0 (silence) to 1 (loud), smoothed so it falls back gently.
    private(set) var level: Float = 0
    private(set) var isRunning = false

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let usesSampleData: Bool

    init() {
        usesSampleData = false
    }

    /// A fixed level for previews and screenshots; never touches the microphone.
    init(sampleLevel: Float) {
        usesSampleData = true
        level = sampleLevel
        isRunning = true
    }

    func start() {
        guard !usesSampleData, !isRunning else { return }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startEngine()
        case .undetermined:
            Task {
                if await AVAudioApplication.requestRecordPermission() { start() }
            }
        default:
            break
        }
    }

    func stop() {
        guard !usesSampleData else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        level = 0
    }

    /// Picks up a change of default input device.
    func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap { [weak self] rms in
            Task { @MainActor in self?.update(rms: rms) }
        })
        do {
            try engine.start()
            self.engine = engine
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func update(rms: Float) {
        guard isRunning else { return }
        // Map -50 dBFS…0 dBFS onto 0…1, rising instantly and falling gently.
        let decibels = 20 * log10(max(rms, .leastNonzeroMagnitude))
        let target = min(max((decibels + 50) / 50, 0), 1)
        level = max(target, level * 0.85)
    }

    /// Built outside the main actor: the tap runs on Core Audio's real-time thread.
    private nonisolated static func makeTap(
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
            onLevel(rms)
        }
    }
}
