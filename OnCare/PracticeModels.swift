import Foundation
import Combine

enum PracticeError: Error {
    case invalid, clockChanged, tooShort, unreadable
    var message: String {
        switch self {
        case .clockChanged: return "기기 시간이 이전으로 바뀌었어요. 시간을 확인한 뒤 다시 열거나 세션을 초기화해주세요."
        case .invalid: return "세션을 확인할 수 없거나 운동 시간이 24시간을 넘었어요. 초기화한 뒤 새로 시작해주세요."
        case .tooShort: return "1분 미만은 운동 기록으로 저장하지 않아요. 조금 더 이어가거나 초기화해주세요."
        case .unreadable: return "저장 공간과 기기 상태를 확인해주세요. 세션은 지우지 않았어요."
        }
    }
}

struct WorkoutSession: Codable, Equatable {
    static let types = ["걷기", "러닝", "근력", "스트레칭"]
    static let goals = [10, 20, 30, 60]
    var version = 1
    var id = "timer:" + UUID().uuidString
    var type: String
    var goalMinutes: Int
    var createdAt: Date
    var checkpointAt: Date
    var elapsedSeconds: Double = 0
    var segmentStartedAt: Date?
    var finishedAt: Date?

    var running: Bool { segmentStartedAt != nil }
    func elapsed(at now: Date) throws -> Double {
        try validate(at: now)
        return min(86400, elapsedSeconds + (segmentStartedAt.map { now.timeIntervalSince($0) } ?? 0))
    }
    func validate(at now: Date) throws {
        guard now.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970.isFinite,
              checkpointAt.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970 > 0,
              version == 1, id.hasPrefix("timer:"), UUID(uuidString: String(id.dropFirst(6))) != nil,
              Self.types.contains(type), Self.goals.contains(goalMinutes),
              checkpointAt >= createdAt, elapsedSeconds.isFinite, (0...86400).contains(elapsedSeconds),
              elapsedSeconds <= checkpointAt.timeIntervalSince(createdAt) + 0.001,
              segmentStartedAt == nil || finishedAt == nil else { throw PracticeError.invalid }
        guard now >= checkpointAt else { throw PracticeError.clockChanged }
        if let start = segmentStartedAt {
            guard start.timeIntervalSince1970.isFinite, start >= createdAt, start <= checkpointAt,
                  elapsedSeconds <= start.timeIntervalSince(createdAt) + 0.001,
                  elapsedSeconds + now.timeIntervalSince(start) <= 86400.001 else { throw PracticeError.invalid }
        }
        if let end = finishedAt {
            guard end.timeIntervalSince1970.isFinite, end >= createdAt, end == checkpointAt,
                  elapsedSeconds >= 60 else { throw PracticeError.invalid }
        }
    }
}

@MainActor final class WorkoutTimerStore: ObservableObject {
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var issue: String?
    private let url: URL
    private var lastObservedAt: Date?
    init(directory: URL? = nil, now: Date = Date()) {
        let folder = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = folder.appendingPathComponent("workout-session-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 8192 else { throw PracticeError.invalid }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            session = try decoder.decode(WorkoutSession.self, from: data)
            try settleLimit(at: now)
            try session?.validate(at: now); lastObservedAt = now
        } catch { issue = (error as? PracticeError)?.message ?? PracticeError.invalid.message }
    }
    func observe(at now: Date) {
        guard session != nil else { return }
        do {
            try settleLimit(at: now)
            try session?.validate(at: now)
            if let lastObservedAt, now < lastObservedAt { throw PracticeError.clockChanged }
            self.lastObservedAt = now
            if issue == PracticeError.clockChanged.message { issue = nil }
        } catch { issue = (error as? PracticeError)?.message ?? PracticeError.invalid.message }
    }
    private func checked(at now: Date) throws -> WorkoutSession {
        try settleLimit(at: now)
        guard let session else { throw PracticeError.invalid }
        try session.validate(at: now)
        if let lastObservedAt, now < lastObservedAt { throw PracticeError.clockChanged }
        return session
    }
    private func settleLimit(at now: Date) throws {
        guard let current = session, let start = current.segmentStartedAt,
              current.elapsedSeconds.isFinite, (0...86400).contains(current.elapsedSeconds) else { return }
        let limit = start.addingTimeInterval(86400 - current.elapsedSeconds)
        guard now >= limit else { return }
        guard now >= current.checkpointAt, lastObservedAt.map({ now >= $0 }) ?? true else { throw PracticeError.clockChanged }
        // Validate the original state at its limit before changing an expired running session.
        try current.validate(at: limit)
        var next = current; next.elapsedSeconds = 86400; next.segmentStartedAt = nil; next.checkpointAt = now
        try persist(next, at: now)
    }
    private func persist(_ next: WorkoutSession, at now: Date) throws {
        try next.validate(at: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        do { try encoder.encode(next).write(to: url, options: [.atomic, .completeFileProtection]) }
        catch { throw PracticeError.unreadable }
        session = next; lastObservedAt = now; issue = nil
    }
    func start(type: String, goal: Int, at now: Date = Date()) throws {
        guard session == nil, issue == nil else { throw PracticeError.invalid }
        try persist(WorkoutSession(type: type, goalMinutes: goal, createdAt: now, checkpointAt: now, segmentStartedAt: now), at: now)
    }
    func pause(at now: Date = Date()) throws {
        var next = try checked(at: now)
        guard next.running else { return }
        next.elapsedSeconds = try next.elapsed(at: now); next.segmentStartedAt = nil; next.checkpointAt = now
        try persist(next, at: now)
    }
    func resume(at now: Date = Date()) throws {
        var next = try checked(at: now)
        guard !next.running, next.finishedAt == nil, next.elapsedSeconds < 86400 else { throw PracticeError.invalid }
        next.segmentStartedAt = now; next.checkpointAt = now; try persist(next, at: now)
    }
    func checkpoint(at now: Date = Date()) throws {
        var next = try checked(at: now)
        if next.finishedAt != nil { return }
        next.checkpointAt = now; try persist(next, at: now)
    }
    func reset() throws {
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { throw PracticeError.unreadable }
        session = nil; issue = nil; lastObservedAt = nil
    }
    func hasSavedRecord(in journal: Journal) -> Bool {
        guard let id = session?.id else { return false }
        return journal.entries.contains { $0.id == id && $0.kind == "운동" }
    }
    func mayFinish(in journal: Journal) -> Bool { issue == nil || hasSavedRecord(in: journal) }
    @discardableResult func finish(in journal: Journal, at now: Date = Date()) throws -> String {
        guard let current = session else { throw PracticeError.invalid }
        // A journal write may succeed just before the process stops. Its stable ID proves the save.
        if let saved = journal.entries.first(where: { $0.id == current.id }) {
            guard saved.kind == "운동" else { throw PracticeError.invalid }
            return finishCleanup(message: "이미 저장된 운동 기록을 확인했어요. 중복으로 추가하지 않았어요.")
        }
        var next = try checked(at: now)
        let seconds = try next.elapsed(at: now)
        guard seconds >= 60 else { throw PracticeError.tooShort }
        if next.finishedAt == nil {
            next.elapsedSeconds = seconds; next.segmentStartedAt = nil; next.finishedAt = now; next.checkpointAt = now
            // Freeze the result before writing the journal so retries cannot add extra time.
            try persist(next, at: now)
        }
        let entry = Entry(id: next.id, date: next.finishedAt!, kind: "운동", value: next.elapsedSeconds / 60, note: "운동 타이머로 기록", type: next.type)
        guard journal.save(entry) else { throw PracticeError.unreadable }
        return finishCleanup(message: "\(next.type) \(number(next.elapsedSeconds / 60))분을 저장했어요.")
    }
    private func finishCleanup(message: String) -> String {
        do { try reset(); return message }
        catch { issue = "운동 기록은 저장됐어요. 세션 정리가 되지 않아 완료를 다시 눌러주세요."; return message + " 세션 정리를 다시 시도해주세요." }
    }
}

enum PracticeWindow: Int, CaseIterable, Identifiable {
    case week = 7, month = 30
    var id: Int { rawValue }
    var title: String { "\(rawValue)일" }
}

struct PracticeMetric {
    var value: Double?
    var recordedDays: Int
}
struct PracticePeriod: Identifiable {
    var id: Date { start }
    var start: Date
    var end: Date
    var exercise: PracticeMetric
    var sleep: PracticeMetric
    var mood: PracticeMetric
}
struct RoutinePracticeDay: Identifiable {
    var date: Date
    var completed: Bool
    var id: Date { date }
}
struct RoutinePractice {
    var days: [RoutinePracticeDay]
    var streak: Int
    var completedCount: Int { days.filter(\.completed).count }
}
enum PracticeSummary {
    static func key(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    static func routine(_ id: String, checks: [String: [String: Bool]], now: Date = Date(), calendar: Calendar = .current) -> RoutinePractice {
        let today = calendar.startOfDay(for: now)
        func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func completed(_ day: Date) -> Bool { checks[key(day, calendar: calendar)]?[id] == true }
        let days = (-6...0).map { RoutinePracticeDay(date: date($0), completed: completed(date($0))) }
        var offset = completed(today) ? 0 : -1, streak = 0
        while streak <= checks.count, completed(date(offset)) { streak += 1; offset -= 1 }
        return RoutinePractice(days: days, streak: streak)
    }
    static func period(entries: [Entry], start: Date, end: Date, calendar: Calendar = .current) -> PracticePeriod {
        let records = entries.filter { $0.date >= start && $0.date < end }
        func metric(_ kind: String, total: Bool) -> PracticeMetric {
            let values = records.filter { $0.kind == kind }
            guard !values.isEmpty else { return PracticeMetric(value: nil, recordedDays: 0) }
            var last: [Date: Entry] = [:]
            for e in values { let day = calendar.startOfDay(for: e.date); if let previous = last[day] {
                    if previous.date < e.date || (previous.date == e.date && previous.id < e.id) { last[day] = e }
                } else { last[day] = e } }
            let value = total ? values.reduce(0) { $0 + $1.value } : last.values.reduce(0) { $0 + $1.value } / Double(last.count)
            return PracticeMetric(value: value, recordedDays: last.count)
        }
        return PracticePeriod(start: start, end: end, exercise: metric("운동", total: true), sleep: metric("수면", total: false), mood: metric("마음", total: false))
    }
    static func completedPeriods(entries: [Entry], window: PracticeWindow, now: Date = Date(), calendar: Calendar = .current) -> [PracticePeriod] {
        let today = calendar.startOfDay(for: now)
        let recent = calendar.date(byAdding: .day, value: -window.rawValue, to: today)!
        let prior = calendar.date(byAdding: .day, value: -window.rawValue, to: recent)!
        return [period(entries: entries, start: recent, end: today, calendar: calendar), period(entries: entries, start: prior, end: recent, calendar: calendar)]
    }
    static func completedWeeks(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> [PracticePeriod] {
        completedPeriods(entries: entries, window: .week, now: now, calendar: calendar)
    }
    static func daily(entries: [Entry], in period: PracticePeriod, calendar: Calendar = .current) -> [PracticePeriod] {
        let records = entries.filter { $0.date >= period.start && $0.date < period.end }
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        var result: [PracticePeriod] = [], day = period.start
        while day < period.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            result.append(Self.period(entries: grouped[day] ?? [], start: day, end: min(next, period.end), calendar: calendar))
            day = next
        }
        return result
    }
    static func shareText(recent: PracticePeriod, prior: PracticePeriod, window: PracticeWindow, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR"); formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy.MM.dd"
        func dates(_ period: PracticePeriod) -> String {
            let last = calendar.date(byAdding: .day, value: -1, to: period.end)!
            return formatter.string(from: period.start) + " – " + formatter.string(from: last)
        }
        func metric(_ title: String, _ current: PracticeMetric, _ previous: PracticeMetric, _ unit: String) -> String {
            func value(_ metric: PracticeMetric) -> String {
                (metric.value.map { number($0) + unit } ?? "기록 없음") + " (기록 \(metric.recordedDays)/\(window.rawValue)일)"
            }
            return title + ": " + value(current) + " / 이전 " + value(previous)
        }
        return ["온케어 · \(window.title) 기록 요약", "최근: " + dates(recent), "이전: " + dates(prior),
                metric("운동 합계", recent.exercise, prior.exercise, "분"),
                metric("수면 평균", recent.sleep, prior.sleep, "시간"),
                metric("마음 평균", recent.mood, prior.mood, "점"),
                "오늘은 제외합니다. 수면·마음은 하루 마지막 기록의 평균이며, 기록 없는 날은 제외합니다."].joined(separator: "\n")
    }
}
