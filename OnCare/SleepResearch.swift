import Foundation
import AVFoundation
import CryptoKit
import OnnxRuntimeBindings

struct SleepResearchSummary: Codable {
    var model = "apsaa-pilot-v1"
    var analyzed = 0
    var candidates = 0
    var skipped = 0
    var researchOnly = true
}

/// A per-session, bounded in-memory research pipeline. No audio file or network API.
final class SleepResearch {
    static let hash = "ccc3c94646cab11d53fab9d2bedae8c777c3c5ec3f0926a421c35fe44c46400c"
    static var available: Bool { Bundle.main.url(forResource: "research-sleep", withExtension: "onnx") != nil }
    private let lock = NSLock(), queue = DispatchQueue(label: "oncare.research.sleep", qos: .utility)
    private let environment: ORTEnv
    private let session: ORTSession
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private var samples = [Float]()
    private var summary = SleepResearchSummary()
    private var busy = false, closed = false
    init(format: AVAudioFormat) throws {
        guard let path = Bundle.main.url(forResource: "research-sleep", withExtension: "onnx"),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 4000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { throw CareError.invalid }
        let bytes = try Data(contentsOf: path)
        guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.hash else { throw CareError.invalid }
        self.target = target; self.converter = converter
        environment = try ORTEnv(loggingLevel: .error)
        let options = try ORTSessionOptions(); try options.setIntraOpNumThreads(1)
        session = try ORTSession(env: environment, modelPath: path.path, sessionOptions: options)
        samples.reserveCapacity(120000)
    }
    func add(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 4000 / buffer.format.sampleRate) + 128)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return buffer
        }
        guard error == nil, status != .error, let channel = output.floatChannelData?[0] else {
            // Reset the partial epoch: discontinuous audio must never be stitched together.
            samples.removeAll(keepingCapacity: true); summary.skipped += 1; converter.reset(); return
        }
        for index in 0..<Int(output.frameLength) {
            samples.append(channel[index])
            if samples.count == 120000 {
                let epoch = samples; samples = []; samples.reserveCapacity(120000)
                if busy { summary.skipped += 1 }
                else { busy = true; queue.async { self.analyze(epoch) } }
            }
        }
    }
    private func analyze(_ audio: [Float]) {
        var candidate: Bool?
        do {
            let energy = audio.reduce(0.0) { $0 + Double($1)*Double($1) } / Double(audio.count)
            guard energy >= pow(10, -6.5), audio.filter({ abs($0) >= 0.99 }).count <= 1200 else { throw CareError.invalid }
            let features = try ResearchMel.extract(audio)
            let bytes = features.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
            let input = try ORTValue(tensorData: bytes, elementType: .float, shape: [1,64,2998])
            let outputs = try session.run(withInputs: ["log_mel": input], outputNames: ["candidate_probabilities"], runOptions: nil)
            guard let value = outputs["candidate_probabilities"] else { throw CareError.invalid }
            let data = try value.tensorData()
            guard data.length == 8 else { throw CareError.invalid }
            var probabilities = [Float](repeating: 0, count: 2)
            probabilities.withUnsafeMutableBytes { data.getBytes($0.baseAddress!, length: 8) }
            let score = probabilities[1]
            guard score.isFinite, (0...1).contains(score) else { throw CareError.invalid }
            candidate = Double(score) >= 0.3778610110282898
        } catch { candidate = nil }
        lock.lock(); defer { lock.unlock() }
        if !closed { if let value = candidate { summary.analyzed += 1; if value { summary.candidates += 1 } } else { summary.skipped += 1 } }
        busy = false
    }
    func snapshot() -> SleepResearchSummary { lock.lock(); defer { lock.unlock() }; return summary }
    func close() -> SleepResearchSummary {
        lock.lock(); defer { lock.unlock() }
        closed = true; if busy { summary.skipped += 1 }
        samples.removeAll(keepingCapacity: false); converter.reset(); return summary
    }
}
