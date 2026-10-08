import AVFoundation
import Foundation
import Observation

enum AudioStorage {
    static var root: URL { URL.documentsDirectory }
    static var warmups: URL { folder("Warmups") }
    static var takes: URL { folder("Takes") }

    private static func folder(_ name: String) -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies an imported file (from the Files picker) into the Warmups folder; returns the stored name.
    static func importWarmup(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let name = "\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)"
        try FileManager.default.copyItem(at: source, to: warmups.appending(path: name))
        return name
    }
}

@Observable
final class TrackPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause(); isPlaying = false; timer?.invalidate() }
        else {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play(); isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let p = self?.player, p.duration > 0 else { return }
                self?.progress = p.currentTime / p.duration
            }
        }
    }

    func stop() {
        player?.stop(); player = nil
        timer?.invalidate(); isPlaying = false; progress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false; progress = 1; timer?.invalidate()
    }
}

@Observable
final class TakeRecorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var currentName: String?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        let name = "take-\(Int(Date().timeIntervalSince1970)).m4a"
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try AVAudioRecorder(url: AudioStorage.takes.appending(path: name), settings: settings)
        recorder?.record()
        currentName = name
        isRecording = true
    }

    /// Stops and returns the saved file name.
    func stop() -> String? {
        recorder?.stop(); recorder = nil
        isRecording = false
        defer { currentName = nil }
        return currentName
    }
}
