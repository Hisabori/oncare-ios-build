import SwiftUI
import AVFoundation

struct SleepSoundBin: Codable, Equatable {
    var seconds: Double
    var rmsDBFS: Double
    var peakDBFS: Double
}
final class SleepSoundAccumulator {
    private let lock = NSLock()
    private var sum = 0.0, peak = 0.0, seconds = 0.0
    private var count = 0, bins = 0
    func add(_ samples: UnsafeBufferPointer<Float>, rate: Double) -> SleepSoundBin? {
        lock.lock(); defer { lock.unlock() }
        guard rate.isFinite, rate > 0, bins < 480 else { return nil }
        for sample in samples { let value = Double(sample); if value.isFinite { sum += value * value; peak = max(peak, abs(value)); count += 1 } }
        seconds += Double(samples.count) / rate
        if seconds >= 60 { bins += 1; return drain() }
        return nil
    }
    func finish() -> SleepSoundBin? { lock.lock(); defer { lock.unlock() }; return drain() }
    private func drain() -> SleepSoundBin? {
        guard count > 0, seconds > 0 else { return nil }
        let result = SleepSoundBin(seconds: seconds, rmsDBFS: Self.db(sqrt(sum / Double(count))), peakDBFS: Self.db(peak))
        sum = 0; peak = 0; count = 0; seconds = 0; return result
    }
    static func db(_ value: Double) -> Double { value.isFinite && value > 0 ? min(0, max(-120, 20 * log10(value))) : -120 }
}
struct SleepSoundSession: Codable, Identifiable {
    var id = UUID().uuidString
    var started = Date()
    var ended: Date?
    var reason = "측정 중"
    var threshold = -35.0
    var bins: [SleepSoundBin] = []
    var research: SleepResearchSummary? = nil
    var measuredMinutes: Double { bins.reduce(0) { $0 + $1.seconds } / 60 }
    var loudMinutes: Double { bins.filter { $0.rmsDBFS >= threshold }.reduce(0) { $0 + $1.seconds } / 60 }
}
@MainActor final class SleepSoundStore: ObservableObject {
    static let shared = SleepSoundStore()
    @Published private(set) var sessions: [SleepSoundSession] = []
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var message = ""
    private var engine: AVAudioEngine?
    private var accumulator: SleepSoundAccumulator?
    private var researchAnalyzer: SleepResearch?
    private var observers: [NSObjectProtocol] = []
    private let file: URL
    init(directory: URL? = nil) {
        file = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("sleep-sound-v1.json")
        if let data = try? Data(contentsOf: file), data.count <= 1000000, let saved = try? JSONDecoder().decode([SleepSoundSession].self, from: data) {
            sessions = Array(saved.prefix(7)).filter { $0.bins.count <= 480 && [-45.0,-35.0,-25.0].contains($0.threshold) && $0.bins.allSatisfy { $0.seconds.isFinite && $0.seconds > 0 && $0.seconds <= 65 && $0.rmsDBFS.isFinite && (-120...0).contains($0.rmsDBFS) && $0.peakDBFS.isFinite && (-120...0).contains($0.peakDBFS) } }
            for index in sessions.indices {
                if let summary = sessions[index].research, !summary.researchOnly || summary.model != "apsaa-pilot-v1" || summary.analyzed < 0 || summary.analyzed > 960 || summary.candidates < 0 || summary.candidates > summary.analyzed || summary.skipped < 0 || summary.skipped > 2000 { sessions[index].research = nil }
            }
            for index in sessions.indices where sessions[index].ended == nil { sessions[index].ended = sessions[index].started.addingTimeInterval(sessions[index].bins.reduce(0) { $0 + $1.seconds }); sessions[index].reason = "앱 종료·중단 후 복구된 요약" }
        }
    }
    func start(threshold: Double, research: Bool = false) {
        guard !running, !starting, [-45.0,-35.0,-25.0].contains(threshold) else { return }
        guard !research || SleepResearch.available else { message = "연구 모델이 포함되지 않은 빌드예요."; return }
        starting = true
        AVAudioSession.sharedInstance().requestRecordPermission { granted in Task { @MainActor in
            guard self.starting else { return }; self.starting = false
            guard granted else { self.message = "마이크 권한이 필요해요. 기기 설정에서 변경할 수 있어요."; return }
            self.begin(threshold: threshold, research: research)
        } }
    }
    private func begin(threshold: Double, research: Bool) {
        do {
            let audio = AVAudioSession.sharedInstance(); try audio.setCategory(.record, mode: .measurement); try audio.setActive(true)
            let engine = AVAudioEngine(); let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CareError.invalid }
            let collector = SleepSoundAccumulator()
            let analyzer: SleepResearch?
            if research { analyzer = try SleepResearch(format: format) } else { analyzer = nil }
            researchAnalyzer = analyzer
            let session = SleepSoundSession(threshold: threshold, research: analyzer?.snapshot())
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                analyzer?.add(buffer)
                guard let channel = buffer.floatChannelData?[0] else { return }
                if let bin = collector.add(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), rate: buffer.format.sampleRate) { Task { @MainActor in self.receive(bin, id: session.id) } }
            }
            self.engine = engine; accumulator = collector
            try engine.start(); sessions.insert(session, at: 0); sessions = Array(sessions.prefix(7)); running = true; message = "측정 중 · 첫 요약은 약 1분 뒤 표시돼요."; save()
            for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, .AVAudioEngineConfigurationChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor in if self.running { self.stop(reason: "마이크 경로 변경·통화 등으로 중단") } } })
            }
        } catch { engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil; accumulator = nil; _ = researchAnalyzer?.close(); researchAnalyzer = nil; try? AVAudioSession.sharedInstance().setActive(false); message = "마이크 또는 연구 모델을 시작하지 못했어요. 권한·모델 포함 여부를 확인해주세요." }
    }
    private func receive(_ bin: SleepSoundBin, id: String) {
        guard running, !sessions.isEmpty, sessions[0].id == id, sessions[0].bins.count < 480 else { return }
        sessions[0].bins.append(bin); sessions[0].research = researchAnalyzer?.snapshot(); save()
        if sessions[0].bins.count >= 480 { stop(reason: "최대 8시간 측정 완료") }
    }
    func stop(reason: String = "직접 종료") {
        starting = false
        guard running else { return }; running = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        sessions[0].research = researchAnalyzer?.close(); researchAnalyzer = nil
        if let bin = accumulator?.finish(), sessions[0].bins.count < 480 { sessions[0].bins.append(bin) }
        accumulator = nil; sessions[0].ended = Date(); sessions[0].reason = reason
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        message = reason; save()
    }
    func deleteHistory() { guard !running, !starting else { return }; do { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }; sessions = []; message = "소리 요약을 삭제했어요." } catch { message = "삭제하지 못했어요." } }
    private func save() {
        do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(sessions).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); var url = file; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values) }
        catch { message = "요약 저장에 실패했어요. 측정을 종료하고 저장 공간을 확인해주세요."; if running { stop(reason: "저장 오류로 중단") } }
    }
}
struct SleepSoundView: View {
    @StateObject private var store = SleepSoundStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var threshold = -35.0
    @State private var deleting = false
    @State private var research = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("밤사이 소리, 기기 안에서").font(.title2.bold())
            Text("원음·대화는 저장하거나 전송하지 않아요. 기본 측정은 1분 단위 소리 크기를 남겨요. 실제 수면 시간·수면 단계·코골이·무호흡을 판별하지 않습니다. 주변 소음이나 함께 자는 사람의 소리도 포함될 수 있어요.").font(.subheadline)
            Text("휴대폰을 침구로 덮지 말고 안전한 곳에 두세요. 측정 전 충전 상태와 저장 공간을 확인하고, 같은 공간 사람의 동의를 받아주세요.").font(.caption).foregroundStyle(.secondary)
            Picker("큰 소리 구간 기준", selection: $threshold) { Text("민감 -45").tag(-45.0); Text("기본 -35").tag(-35.0); Text("둔감 -25").tag(-25.0) }.disabled(store.running || store.starting)
            Text("dBFS는 마이크의 상대적인 신호 크기이며 실제 소음계 dB가 아닙니다.").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("연구용 호흡 후보 분석", isOn: $research).disabled(store.running || store.starting || !SleepResearch.available)
                Text(SleepResearch.available ? "켜면 30초 음향을 메모리에서만 분석하고 후보 구간 수만 남겨요. 2명 평가에서 균형 정확도 62.5%인 초기 모델로, 건강 판단·무호흡 경고에 사용할 수 없어요." : "이 빌드에는 연구 모델이 포함되지 않았어요. 소리 크기 기록은 사용할 수 있어요.").font(.caption).foregroundStyle(.secondary)
            }.careCard()
            if store.running || store.starting { Button("측정 종료") { store.stop() }.buttonStyle(.borderedProminent) }
            else { Button("마이크 소리 측정 시작") { store.start(threshold: threshold, research: research) }.buttonStyle(.borderedProminent).accessibilityIdentifier("sleep-sound-start") }
            Text(store.message).font(.subheadline).foregroundStyle(.secondary)
            ForEach(store.sessions) { session in VStack(alignment: .leading, spacing: 10) {
                Text(session.started.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Text("측정 \(Int(session.measuredMinutes))분 · 기준 이상 \(Int(session.loudMinutes))분")
                Text(session.reason + " · 기준 \(Int(session.threshold)) dBFS").font(.caption).foregroundStyle(.secondary)
                if let summary = session.research {
                    Text("연구용 후보 구간 \(summary.candidates) / 분석 \(summary.analyzed) · 판정 보류 \(summary.skipped)").font(.subheadline)
                    Text("30초 구간 기준이며 무호흡 횟수·수면 단계·정상 판정이 아닙니다.").font(.caption).foregroundStyle(.secondary)
                }
                if !session.bins.isEmpty { ScrollView(.horizontal) { HStack(alignment: .bottom, spacing: 2) { ForEach(Array(session.bins.enumerated()), id: \.offset) { _, bin in RoundedRectangle(cornerRadius: 2).fill(bin.rmsDBFS >= session.threshold ? Color.orange : Color.teal).frame(width: 5, height: max(3, (bin.rmsDBFS + 120) / 2)) } }.frame(height: 65, alignment: .bottom) }.accessibilityLabel("1분 단위 상대 소리 크기 추이") }
            }.careCard() }
            Text("최근 7회, 회당 최대 8시간을 보관해요. 통화·마이크 경로 변경·앱 강제 종료로 중단될 수 있으며 자동 재시작하지 않습니다. 앱 삭제 시 요약도 삭제됩니다.").font(.caption).foregroundStyle(.secondary)
            Button("소리 요약 전체 삭제", role: .destructive) { deleting = true }.disabled(store.running || store.starting)
        }.padding(22) }.background(Color(.systemGroupedBackground)).navigationTitle("수면 소리 기록").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }.confirmationDialog("소리 요약을 모두 삭제할까요?", isPresented: $deleting) { Button("삭제", role: .destructive) { store.deleteHistory() } } }
    }
}
