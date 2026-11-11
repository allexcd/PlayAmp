import AppKit
import AVFoundation
import SFBAudioEngine
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// Turns the audio tap's ~0.1 s blocks into ~40 spectrum frames a second. Each block is cut
/// into overlapping 2048-sample windows; their results are released one by one at the pace the
/// audio plays, so the analyzer moves continuously instead of jumping ten times a second.
final class Spectrum: @unchecked Sendable {
    static let bands = 20
    private static let window = 2048, slices = 4
    private let lock = NSLock()
    private var frames: [(time: TimeInterval, values: [Float])] = []
    private var latest = Array(repeating: Float(0), count: bands)
    private var history: [Float] = []   // last `window` samples, so slices can overlap block edges

    /// The newest frame (used by tests and as a fallback).
    func read() -> [Float] { lock.lock(); defer { lock.unlock() }; return latest }
    /// The frame due at `time` (seconds of system uptime); older frames are dropped.
    func read(at time: TimeInterval) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        while frames.count > 1, frames[1].time <= time { frames.removeFirst() }
        if let first = frames.first, first.time <= time { latest = first.values }
        return latest
    }
    /// Runs on the analysis queue, never on the main thread.
    func analyze(_ samples: [Float], rate: Double, arrival: TimeInterval) {
        guard !samples.isEmpty else { return }
        let hop = max(1, samples.count / Self.slices)
        var output: [(TimeInterval, [Float])] = []
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + hop)
            history.append(contentsOf: samples[start..<end])
            if history.count > Self.window { history.removeFirst(history.count - Self.window) }
            output.append((arrival + Double(start) / rate, Self.bandLevels(history, rate: rate)))
            start = end
        }
        lock.lock()
        frames.removeAll { $0.time < arrival - 0.5 }   // stale after a pause or seek
        frames.append(contentsOf: output.map { (time: $0.0, values: $0.1) })
        latest = output.last?.1 ?? latest
        lock.unlock()
    }
    /// Log-spaced Goertzel filters over a Hann-windowed block.
    private static func bandLevels(_ samples: [Float], rate: Double) -> [Float] {
        let count = Float(samples.count)
        let window = (0..<samples.count).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(samples.count))) }
        return (0..<bands).map { band -> Float in
            let frequency = 55 * pow(1.34, Double(band))
            let coefficient = Float(2 * cos(2 * .pi * frequency / rate))
            var a: Float = 0; var b: Float = 0
            for i in 0..<samples.count {
                let c = samples[i] * window[i] + coefficient * a - b; b = a; a = c
            }
            let power = max(0, a*a + b*b - coefficient*a*b)
            return min(1, max(0, (20 * log10(sqrt(power) / count + 0.00001) + 75) / 65))
        }
    }
}
final class Playback: NSObject, AudioPlayer.Delegate {
    let player = AudioPlayer()
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    let spectrum = Spectrum()
    let analysisSlot = DispatchSemaphore(value: 1)
    let analysis = DispatchQueue(label: "PlayAmp.spectrum", qos: .utility)
    var onEnd: (() -> Void)?
    var onError: ((String) -> Void)?
    static let frequencies: [Float] = [31,62,125,250,500,1000,2000,4000,8000,16000]
    override init() {
        super.init(); player.delegate = self
        for (i, band) in eq.bands.enumerated() { band.filterType = .parametric; band.frequency = Self.frequencies[i]; band.bandwidth = 1; band.bypass = false }
        player.modifyProcessingGraph { engine in
            engine.attach(self.eq)
            let format = self.player.sourceNode.outputFormat(forBus: 0)
            engine.disconnectNodeOutput(self.player.sourceNode)
            engine.connect(self.player.sourceNode, to: self.eq, format: format)
            engine.connect(self.eq, to: engine.mainMixerNode, format: format)
        }
        player.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData?[0], self.analysisSlot.wait(timeout: .now()) == .success else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            // While paused the engine keeps delivering silence; don't spend time analyzing it.
            guard samples.contains(where: { abs($0) > 1e-5 }) else { self.analysisSlot.signal(); return }
            let rate = buffer.format.sampleRate
            let arrival = ProcessInfo.processInfo.systemUptime
            self.analysis.async { self.spectrum.analyze(samples, rate: rate, arrival: arrival); self.analysisSlot.signal() }
        }
    }
    func apply(_ s: Session) {
        player.mainMixerNode.outputVolume = s.volume
        player.mainMixerNode.pan = s.balance
        eq.bypass = !s.eqEnabled
        eq.globalGain = s.safePreamp
        for (i, gain) in s.bands.prefix(10).enumerated() { eq.bands[i].gain = gain }
    }
    func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
        engine.disconnectNodeOutput(eq); engine.connect(eq, to: engine.mainMixerNode, format: format); return eq
    }
    func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: PCMDecoding, error: Error, framesRendered: AVAudioFramePosition) {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) { DispatchQueue.main.async { self.onEnd?() } }
    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
}
