import Foundation
import Combine

let categories = ["마음", "체중", "운동", "수면", "물", "걸음"]
let moodNames = ["힘들어요", "조금 지쳐요", "보통이에요", "좋아요", "아주 좋아요"]
func number(_ n: Double) -> String { n.formatted(.number.grouping(.never).locale(Locale(identifier: "ko_KR")).precision(.fractionLength(0...1))) }
func rawNumber(_ n: Double) -> String { n == n.rounded() ? String(format: "%.0f", n) : String(n) }
func inputNumber(_ text: String) -> Double? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.contains(",") {
        guard text.range(of: #"^[+-]?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        text = text.replacingOccurrences(of: ",", with: "")
    }
    guard let value = Double(text), value.isFinite else { return nil }
    return value
}
func isFileSelectionCancelled(_ error: Error) -> Bool {
    let error = error as NSError
    return (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
        || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
}
func unit(_ kind: String) -> String {
    switch kind { case "마음": return "점"; case "체중": return "kg"; case "운동": return "분"; case "수면": return "시간"; case "걸음": return "걸음"; default: return "ml" }
}
func symbol(_ kind: String) -> String {
    switch kind { case "마음": return "face.smiling"; case "체중": return "scalemass"; case "운동": return "figure.walk"; case "수면": return "moon"; case "걸음": return "figure.walk"; default: return "drop" }
}
func dateKey(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
}
func koreanDate(_ date: Date, weekday: Bool = false) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = weekday ? "M월 d일 EEEE" : "M월 d일"; return f.string(from: date) }
func dayOffset(_ n: Int, from: Date = Date()) -> Date { Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: from))! }
func monday(_ date: Date = Date()) -> Date { dayOffset(-((Calendar.current.component(.weekday, from: date) + 5) % 7), from: date) }

struct Entry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var kind: String
    var value: Double
    var note: String = ""
    var type: String? = nil
    var sets: Int? = nil
    var reps: Int? = nil
    var source: String? = nil
    var bedTime: Date? = nil
    var wakeTime: Date? = nil
    var awakeMinutes: Double? = nil
    var sleep: SleepDetails? = nil
}
struct CareGoals: Codable, Equatable {
    var weight: Double = 0
    var exercise: Double = 120
    var water: Double = 1500
    var sleep: Double = 7
    func validate() throws {
        guard weight.isFinite, exercise.isFinite, water.isFinite, sleep.isFinite,
              (0...500).contains(weight), exercise > 0, exercise <= 10080,
              water > 0, water <= 20000, sleep > 0, sleep <= 24 else { throw CareError.invalid }
    }
}
struct Routine: Codable, Identifiable, Equatable { var id: String = UUID().uuidString; var title: String }
enum CareError: Error { case invalid, unreadable }
struct CareBackup: Codable {
    var version: Int = 3
    var exportedAt: Double? = Date().timeIntervalSince1970 * 1000
    var entries: [Entry]
    var goals: CareGoals? = nil
    var routines: [Routine]? = nil
    var checks: [String: [String: Bool]]? = nil
    func validate(now: Date = Date()) throws {
        guard (1...3).contains(version), entries.count <= 20000 else { throw CareError.invalid }
        var ids = Set<String>()
        for e in entries {
            let maximum: Double = e.kind == "마음" ? 5 : e.kind == "체중" ? 500 : e.kind == "운동" ? 1440 : e.kind == "수면" ? 24 : e.kind == "걸음" ? 1000000 : 20000
            guard categories.contains(e.kind), e.value.isFinite, e.value > 0, e.value <= maximum,
                  !["마음", "걸음"].contains(e.kind) || e.value.rounded() == e.value,
                  e.date.timeIntervalSince1970 > 0, e.date <= now,
                  !e.id.isEmpty, e.id.count <= 100, ids.insert(e.id).inserted,
                  e.note.count <= 2000, (e.type?.count ?? 0) <= 100, (e.source?.count ?? 0) <= 100 else { throw CareError.invalid }
            if e.bedTime != nil || e.wakeTime != nil || e.awakeMinutes != nil {
                guard e.kind == "수면", let bed = e.bedTime, let wake = e.wakeTime, let awake = e.awakeMinutes, bed.timeIntervalSince1970 > 0, wake <= now, wake == e.date, let hours = SleepPlan.measuredHours(start: bed, end: wake, awake: awake), abs(hours - e.value) < 0.001 else { throw CareError.invalid }
            }
            try e.sleep?.validate(for: e)
            let sets = e.sets ?? 0, reps = e.reps ?? 0
            guard (0...100).contains(sets), (0...1000).contains(reps), (sets == 0) == (reps == 0) else { throw CareError.invalid }
        }
        try goals?.validate()
        guard (routines == nil) == (checks == nil) else { throw CareError.invalid }
        if let routines, let checks {
            guard routines.count <= 8, checks.count <= 3660 else { throw CareError.invalid }
            var known = Set<String>()
            for r in routines {
                guard !r.id.isEmpty, r.id.count <= 100, known.insert(r.id).inserted,
                      !r.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, r.title.count <= 40 else { throw CareError.invalid }
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            for (date, marks) in checks {
                guard date.count == 10, let d = formatter.date(from: date), formatter.string(from: d) == date,
                      d <= Calendar.current.startOfDay(for: now), Set(marks.keys).isSubset(of: known) else { throw CareError.invalid }
            }
        }
    }
    static func decode(_ data: Data) throws -> CareBackup {
        guard data.count <= 5 * 1024 * 1024 else { throw CareError.invalid }
        let json = try JSONSerialization.jsonObject(with: data)
        let decoder = JSONDecoder()
        let result: CareBackup
        if let array = json as? [[String: Any]] {
            // Original iOS stores seconds since 2001; Android backups use Unix milliseconds.
            if let raw = array.first?["date"] as? Double, raw > 100_000_000_000 { decoder.dateDecodingStrategy = .millisecondsSince1970 }
            result = CareBackup(entries: try decoder.decode([Entry].self, from: data))
        } else {
            decoder.dateDecodingStrategy = .millisecondsSince1970
            result = try decoder.decode(CareBackup.self, from: data)
        }
        try result.validate(); return result
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

@MainActor final class Journal: ObservableObject {
    @Published private(set) var calendarRevision = 0
    private var displayedDay = dateKey(Date())
    private var displayedTimeZone = TimeZone.current.identifier
    func refreshCalendar(now: Date = Date(), force: Bool = false) {
        let key = dateKey(now), zone = TimeZone.current.identifier
        guard force || key != displayedDay || zone != displayedTimeZone else { return }
        displayedDay = key; displayedTimeZone = zone; calendarRevision += 1
    }
    @Published private(set) var state = CareBackup(entries: [], goals: CareGoals(), routines: [], checks: [:])
    @Published var notice: String?
    private var readable = true
    private let url: URL
    var entries: [Entry] { state.entries }
    var goals: CareGoals { state.goals ?? CareGoals() }
    var routines: [Routine] { state.routines ?? [] }
    var checks: [String: [String: Bool]] { state.checks ?? [:] }
    init(directory: URL? = nil) {
        let folder = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = folder.appendingPathComponent("care-v3.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) { state = try CareBackup.decode(Data(contentsOf: url)) }
            else {
                let old = folder.appendingPathComponent("journal.json")
                if FileManager.default.fileExists(atPath: old.path) {
                    let legacy = try CareBackup.decode(Data(contentsOf: old)); state.entries = legacy.entries
                    try state.encoded().write(to: url, options: [.atomic, .completeFileProtection])
                }
            }
            state.entries.sort { $0.date > $1.date }
        } catch { readable = false; notice = "기록을 읽지 못했어요. 원본을 보존하기 위해 저장을 중단했어요." }
    }
    @discardableResult func persist(_ next: CareBackup) -> Bool {
        guard readable else { notice = "원본 기록을 읽지 못해 저장할 수 없어요."; return false }
        do {
            try next.validate()
            try next.encoded().write(to: url, options: [.atomic, .completeFileProtection])
            state = next; state.entries.sort { $0.date > $1.date }; return true
        } catch { notice = "저장하지 못했어요. 입력값과 저장 공간을 확인해주세요."; return false }
    }
    @discardableResult func save(_ entry: Entry) -> Bool { var next = state; next.entries.removeAll { $0.id == entry.id }; next.entries.append(entry); return persist(next) }
    func remove(_ id: String) { var next = state; next.entries.removeAll { $0.id == id }; persist(next) }
    func clear() { var next = state; next.entries = []; persist(next) }
    @discardableResult func setGoals(_ goals: CareGoals) -> Bool { var next = state; next.goals = goals; return persist(next) }
    @discardableResult func addRoutine(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard routines.count < 8, !routines.contains(where: { $0.title == title }) else { notice = "이미 있는 루틴이거나 최대 8개를 채웠어요."; return false }
        var next = state; next.routines = routines + [Routine(title: title)]; return persist(next)
    }
    func deleteRoutine(_ id: String) {
        var next = state; next.routines = routines.filter { $0.id != id }; var marks = checks
        for key in Array(marks.keys) { marks[key]?.removeValue(forKey: id) }; next.checks = marks; persist(next)
    }
    func checked(_ id: String, date: Date = Date()) -> Bool { checks[dateKey(date)]?[id] == true }
    func toggle(_ id: String) { var next = state; var marks = checks; marks[dateKey(Date()), default: [:]][id] = !checked(id); next.checks = marks; persist(next) }
    @discardableResult func merge(_ backup: CareBackup) -> Bool {
        do { try backup.validate() } catch { notice = "백업 형식이 맞지 않아요. 기존 기록은 그대로예요."; return false }
        var next = state; let known = Set(entries.map(\.id)); next.entries += backup.entries.filter { !known.contains($0.id) }
        if let goals = backup.goals { next.goals = goals }
        if let routines = backup.routines { next.routines = routines; next.checks = backup.checks }
        return persist(next)
    }
    func latest(_ kind: String, today: Bool = false) -> Entry? { entries.first { $0.kind == kind && (!today || Calendar.current.isDateInToday($0.date)) } }
    func sum(_ kind: String, from: Date, to: Date = Date().addingTimeInterval(1)) -> Double { entries.filter { $0.kind == kind && $0.date >= from && $0.date < to }.reduce(0) { $0 + $1.value } }
    func daily(_ kind: String, from: Date, to: Date = Date().addingTimeInterval(1)) -> [Entry] {
        var values: [Date: Entry] = [:]
        for e in entries where e.kind == kind && e.date >= from && e.date < to {
            let day = Calendar.current.startOfDay(for: e.date)
            if values[day] == nil || values[day]!.date < e.date { values[day] = e }
        }
        return values.values.sorted { $0.date < $1.date }
    }
    func mean(_ kind: String, from: Date, to: Date) -> Double? { let d = daily(kind, from: from, to: to); return d.isEmpty ? nil : d.reduce(0) { $0 + $1.value } / Double(d.count) }
}
