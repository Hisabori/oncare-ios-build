import Foundation
import Combine

enum SleepTrackingError: Error {
    case invalid, clockChanged, tooShort, unreadable
    var message: String {
        switch self {
        case .invalid: return "수면 시각·잠드는 시간·깨어 있던 분을 확인해주세요. 24시간 이내의 기록만 저장할 수 있어요."
        case .clockChanged: return "기기 시각이 이전으로 바뀌었어요. 시각을 확인하거나 취침 기록을 초기화해주세요."
        case .tooShort: return "계산된 수면이 1분 이상이어야 저장할 수 있어요."
        case .unreadable: return "저장 공간을 확인해주세요. 취침 기록은 유지했어요."
        }
    }
}

struct SleepTrackingSession: Codable, Equatable {
    var version = 1
    var id = "sleep-timer:" + UUID().uuidString
    var startedAt: Date
    var checkpointAt: Date
    var finishedAt: Date?
    var latency: Double?
    var awake: Double?

    func validate(at now: Date) throws {
        guard version == 1, id.hasPrefix("sleep-timer:"), UUID(uuidString: String(id.dropFirst(12))) != nil,
              startedAt.timeIntervalSince1970.isFinite, startedAt.timeIntervalSince1970 > 0,
              checkpointAt.timeIntervalSince1970.isFinite, checkpointAt >= startedAt,
              now.timeIntervalSince1970.isFinite else { throw SleepTrackingError.invalid }
        guard now >= checkpointAt else { throw SleepTrackingError.clockChanged }
        if let end = finishedAt {
            guard end == checkpointAt, let latency, let awake,
                  Self.hours(start: startedAt, end: end, latency: latency, awake: awake) != nil else { throw SleepTrackingError.invalid }
        } else {
            guard latency == nil, awake == nil, now.timeIntervalSince(startedAt) <= 86400 else { throw SleepTrackingError.invalid }
        }
    }
    static func hours(start: Date, end: Date, latency: Double, awake: Double) -> Double? {
        let elapsed = end.timeIntervalSince(start) / 60
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              elapsed > 0, elapsed <= 1440, latency.isFinite, (0...90).contains(latency),
              awake.isFinite, awake >= 0, elapsed - latency - awake >= 1 else { return nil }
        return (elapsed - latency - awake) / 60
    }
}

@MainActor final class SleepTrackingStore: ObservableObject {
    @Published private(set) var session: SleepTrackingSession?
    @Published private(set) var issue: String?
    private let url: URL
    private var lastObservedAt: Date?
    init(directory: URL? = nil, now: Date = Date()) {
        let folder = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = folder.appendingPathComponent("sleep-session-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 4096 else { throw SleepTrackingError.invalid }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            session = try decoder.decode(SleepTrackingSession.self, from: data)
            try session?.validate(at: now); lastObservedAt = now
        } catch { issue = (error as? SleepTrackingError)?.message ?? SleepTrackingError.invalid.message }
    }
    func observe(at now: Date) {
        guard let session else { return }
        do {
            try session.validate(at: now)
            if let lastObservedAt, now < lastObservedAt { throw SleepTrackingError.clockChanged }
            self.lastObservedAt = now
            if issue == SleepTrackingError.clockChanged.message { issue = nil }
        } catch { issue = (error as? SleepTrackingError)?.message ?? SleepTrackingError.invalid.message }
    }
    private func checked(at now: Date) throws -> SleepTrackingSession {
        guard let session else { throw SleepTrackingError.invalid }
        try session.validate(at: now)
        if let lastObservedAt, now < lastObservedAt { throw SleepTrackingError.clockChanged }
        return session
    }
    private func persist(_ next: SleepTrackingSession, at now: Date) throws {
        try next.validate(at: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        do { try encoder.encode(next).write(to: url, options: [.atomic, .completeFileProtection]) }
        catch { throw SleepTrackingError.unreadable }
        session = next; lastObservedAt = now; issue = nil
    }
    func start(at now: Date = Date()) throws {
        guard session == nil, issue == nil else { throw SleepTrackingError.invalid }
        try persist(SleepTrackingSession(startedAt: now, checkpointAt: now), at: now)
    }
    func checkpoint(at now: Date = Date()) throws {
        var next = try checked(at: now)
        guard next.finishedAt == nil else { return }
        next.checkpointAt = now; try persist(next, at: now)
    }
    func reset() throws {
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { throw SleepTrackingError.unreadable }
        session = nil; issue = nil; lastObservedAt = nil
    }
    func hasSavedRecord(in journal: Journal) -> Bool {
        guard let id = session?.id else { return false }
        return journal.entries.contains { $0.id == id && $0.kind == "수면" }
    }
    @discardableResult func finish(in journal: Journal, latency: Double, awake: Double, at now: Date = Date()) throws -> String {
        guard let current = session else { throw SleepTrackingError.invalid }
        if let saved = journal.entries.first(where: { $0.id == current.id }) {
            guard saved.kind == "수면" else { throw SleepTrackingError.invalid }
            return cleanup("이미 저장된 수면을 확인했어요. 중복으로 추가하지 않았어요.")
        }
        var next = try checked(at: now)
        if next.finishedAt == nil {
            let elapsed = now.timeIntervalSince(next.startedAt) / 60
            guard latency.isFinite, (0...90).contains(latency), awake.isFinite, awake >= 0 else { throw SleepTrackingError.invalid }
            guard elapsed - latency - awake >= 1 else { throw SleepTrackingError.tooShort }
            guard SleepTrackingSession.hours(start: next.startedAt, end: now, latency: latency, awake: awake) != nil else { throw SleepTrackingError.invalid }
            next.finishedAt = now; next.checkpointAt = now; next.latency = latency; next.awake = awake
            try persist(next, at: now)
        }
        guard let end = next.finishedAt, let recordedLatency = next.latency, let recordedAwake = next.awake,
              let hours = SleepTrackingSession.hours(start: next.startedAt, end: end, latency: recordedLatency, awake: recordedAwake) else { throw SleepTrackingError.invalid }
        let entry = Entry(id: next.id, date: end, kind: "수면", value: hours, note: "취침·기상 시각과 직접 입력한 잠드는 시간으로 계산", bedTime: next.startedAt.addingTimeInterval(recordedLatency * 60), wakeTime: end, awakeMinutes: recordedAwake)
        guard journal.save(entry) else { throw SleepTrackingError.unreadable }
        return cleanup("수면 " + number(hours) + "시간을 저장했어요.")
    }
    private func cleanup(_ message: String) -> String {
        do { try reset(); return message }
        catch { issue = "수면은 저장됐어요. 세션 정리를 위해 기상 완료를 다시 눌러주세요."; return message + " 세션 정리를 다시 시도해주세요." }
    }
}

struct SleepPatternSummary {
    var entries: [Entry]
    var meanHours: Double?
    var bedtimeSpan: Double?
    var wakeSpan: Double?
    static func analyze(_ entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> SleepPatternSummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        var daily: [Date: Entry] = [:]
        for entry in entries where entry.kind == "수면" && entry.date >= start && entry.date <= now {
            let key = calendar.startOfDay(for: entry.date)
            if let old = daily[key] {
                if entry.date > old.date || (entry.date == old.date && entry.id > old.id) { daily[key] = entry }
            } else { daily[key] = entry }
        }
        let values = daily.values.sorted { $0.date < $1.date }
        func minutes(_ date: Date) -> Double { let p = calendar.dateComponents([.hour, .minute], from: date); return Double((p.hour ?? 0) * 60 + (p.minute ?? 0)) }
        return SleepPatternSummary(entries: values, meanHours: values.isEmpty ? nil : values.reduce(0) { $0 + $1.value } / Double(values.count), bedtimeSpan: clockSpan(values.compactMap(\.bedTime).map(minutes)), wakeSpan: clockSpan(values.compactMap(\.wakeTime).map(minutes)))
    }
    static func clockSpan(_ minutes: [Double]) -> Double? {
        guard minutes.count >= 2, minutes.allSatisfy({ $0.isFinite && (0..<1440).contains($0) }) else { return nil }
        let sorted = minutes.sorted()
        var largestGap = sorted[0] + 1440 - sorted.last!
        for index in 1..<sorted.count { largestGap = max(largestGap, sorted[index] - sorted[index-1]) }
        return 1440 - largestGap
    }
}
