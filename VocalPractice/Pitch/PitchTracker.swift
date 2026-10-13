import AVFoundation
import Foundation
import Observation

/// Listens to the microphone and publishes a smoothed pitch line plus a held-note range.
@Observable
final class PitchTracker {
    struct Point: Identifiable {
        let id = UUID()
        let time: Double
        /// Smoothed MIDI pitch; nil where you weren't singing (a gap in the line).
        let midi: Double?
    }

    private(set) var isRunning = false
    private(set) var current: Double?
    private(set) var level: Double = 0
    private(set) var history: [Point] = []
    private(set) var range = RangeTracker()
    private(set) var error: String?

    /// Seconds of history kept for the scrolling graph.
    let historySeconds = 8.0

    private let engine = AVAudioEngine()
    private let analyzer = Analyzer()
    private var smoother = PitchSmoother()
    private var startTime = Date()

    @MainActor
    func start() async {
        guard !isRunning else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Microphone access is off. Turn it on in Settings, Vocal Practice."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // .measurement turns off the voice processing and auto gain that smear pitch.
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            analyzer.configure(sampleRate: format.sampleRate)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [analyzer, weak self] buffer, _ in
                guard let reading = analyzer.consume(buffer) else { return }
                Task { @MainActor in self?.receive(reading) }
            }
            engine.prepare()
            try engine.start()
            startTime = .now
            history.removeAll()
            smoother = PitchSmoother()
            error = nil
            isRunning = true
        } catch {
            self.error = "Couldn't start the microphone: \(error.localizedDescription)"
        }
    }

    @MainActor
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        current = nil
        level = 0
    }

    @MainActor
    func resetRange() { range.reset() }

    @MainActor
    private func receive(_ result: Analyzer.Result) {
        let now = Date().timeIntervalSince(startTime)
        let midi = smoother.push(result.reading)
        current = midi
        level = result.level
        range.update(midi: midi, time: now)
        history.append(Point(time: now, midi: midi))
        history.removeAll { now - $0.time > historySeconds }
    }
}

/// Runs off the main thread on the audio tap: buffers samples and runs YIN every hop.
private final class Analyzer: @unchecked Sendable {
    struct Result { let reading: PitchReading?; let level: Double }

    private let lock = NSLock()
    private var detector = PitchDetector(sampleRate: 48_000)
    private var buffer: [Float] = []
    private var sinceLast = 0
    /// Run detection every ~20 ms, about 50 updates a second.
    private var hop = 1024

    func configure(sampleRate: Double) {
        lock.withLock {
            detector = PitchDetector(sampleRate: sampleRate)
            hop = Int(sampleRate / 50)
            buffer.removeAll(keepingCapacity: true)
            sinceLast = 0
        }
    }

    func consume(_ pcm: AVAudioPCMBuffer) -> Result? {
        guard let channel = pcm.floatChannelData?[0] else { return nil }
        let count = Int(pcm.frameLength)
        return lock.withLock {
            buffer.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            let size = detector.blockSize
            if buffer.count > size { buffer.removeFirst(buffer.count - size) }
            sinceLast += count
            guard buffer.count == size, sinceLast >= hop else { return nil }
            sinceLast = 0
            let reading = detector.detect(buffer)
            var sum: Float = 0
            for s in buffer.suffix(hop) { sum += s * s }
            return Result(reading: reading, level: Double(sqrt(sum / Float(hop))))
        }
    }
}
