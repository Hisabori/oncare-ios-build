import Foundation

enum MedicationAgenda {
    static func matches(_ plan: MedicationPlan, query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let text = (plan.name + " " + plan.instructions).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
        return words.allSatisfy { text.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))) }
    }
    static func summary(_ today: [MedicationPlan], checked: Set<String>, now: Date, calendar: Calendar = .current) -> (due: Int, next: MedicationPlan?) {
        let minute = calendar.component(.hour, from: now)*60 + calendar.component(.minute, from: now)
        let pending = today.filter { !checked.contains($0.id) }
        let next = pending.filter { $0.hour*60 + $0.minute > minute }.sorted {
            let a = $0.hour*60 + $0.minute, b = $1.hour*60 + $1.minute
            return a == b ? $0.id < $1.id : a < b
        }.first
        return (pending.filter { $0.hour*60 + $0.minute <= minute }.count, next)
    }
}
