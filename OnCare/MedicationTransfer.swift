import Foundation

/// One file schema shared by iOS and Android. Health journal backups remain independent.
struct MedicationTransfer: Codable {
    var format = "oncare-medications"
    var version = 1
    let plans: [Plan]
    let checks: [String: [String]]
    struct Plan: Codable {
        let id: String
        let name: String
        let instructions: String
        let hour: Int
        let minute: Int
        let weekdays: [Int]
        let enabled: Bool
        init(_ p: MedicationPlan) { id = p.id; name = p.name; instructions = p.instructions; hour = p.hour; minute = p.minute; weekdays = p.weekdays.sorted(); enabled = p.enabled }
        func value() throws -> MedicationPlan {
            guard Set(weekdays).count == weekdays.count else { throw CareError.invalid }
            let p = MedicationPlan(id: id, name: name, instructions: instructions, hour: hour, minute: minute, weekdays: Set(weekdays), enabled: enabled)
            try p.validate(); return p
        }
    }
    init(_ state: MedicationState) { plans = state.plans.map(Plan.init); checks = state.checks.mapValues { $0.sorted() } }
    func state() throws -> MedicationState {
        guard format == "oncare-medications", version == 1 else { throw CareError.invalid }
        for ids in checks.values { guard Set(ids).count == ids.count else { throw CareError.invalid } }
        let state = MedicationState(plans: try plans.map { try $0.value() }, checks: checks.mapValues { Set($0) })
        try state.validate(); return state
    }
    static func decode(_ data: Data) throws -> MedicationState {
        guard data.count <= 65536 else { throw CareError.invalid }
        return try JSONDecoder().decode(Self.self, from: data).state()
    }
    static func encode(_ state: MedicationState) throws -> Data {
        try state.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Self(state)); guard data.count <= 65536 else { throw CareError.invalid }; return data
    }
}
struct MedicationDay: Identifiable {
    let date: Date
    let confirmed: [MedicationPlan]
    var id: String { dateKey(date) }
}
enum MedicationInsights {
    static func today(_ state: MedicationState, now: Date = Date(), calendar: Calendar = .current) -> [MedicationPlan] {
        let weekday = calendar.component(.weekday, from: now)
        return state.plans.filter { $0.weekdays.contains(weekday) }.sorted { $0.hour == $1.hour ? ($0.minute == $1.minute ? $0.id < $1.id : $0.minute < $1.minute) : $0.hour < $1.hour }
    }
    static func history(_ state: MedicationState, days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [MedicationDay] {
        (0..<min(30, max(1, days))).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let ids = state.checks[dateKey(date)] ?? []
            return MedicationDay(date: date, confirmed: state.plans.filter { ids.contains($0.id) })
        }
    }
}
