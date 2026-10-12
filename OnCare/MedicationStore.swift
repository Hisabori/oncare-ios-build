import Foundation
import Combine
import UserNotifications

struct MedicationPlan: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var instructions = ""
    var hour = 9
    var minute = 0
    var weekdays: Set<Int> = Set(1...7)
    var enabled = true
    func validate() throws {
        guard UUID(uuidString: id) != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, instructions.count <= 200, (0..<24).contains(hour), (0..<60).contains(minute),
              !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)) else { throw CareError.invalid }
    }
    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }
    var daysLabel: String { weekdays.count == 7 ? "매일" : [(2,"월"),(3,"화"),(4,"수"),(5,"목"),(6,"금"),(7,"토"),(1,"일")].filter { weekdays.contains($0.0) }.map { $0.1 }.joined(separator: " · ") }
    var notificationIDs: [String] { enabled ? weekdays.sorted().map { "oncare-med.\(id).\($0)" } : [] }
}
struct MedicationState: Codable {
    var version = 1
    var plans: [MedicationPlan] = []
    var checks: [String: Set<String>] = [:]
    func validate() throws {
        guard version == 1, plans.count <= 8, Set(plans.map(\.id)).count == plans.count, checks.count <= 31 else { throw CareError.invalid }
        for plan in plans { try plan.validate() }
        let ids = Set(plans.map(\.id))
        for (day, completed) in checks {
            guard Self.validDay(day), completed.isSubset(of: ids) else { throw CareError.invalid }
        }
    }
    static func validDay(_ key: String) -> Bool {
        guard key.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: key) else { return false }; return formatter.string(from: date) == key
    }
}
@MainActor protocol MedicationNotifications {
    func authorize() async throws -> Bool
    func allowed() async -> Bool
    func apply(_ plans: [MedicationPlan]) async throws
}
@MainActor struct SystemMedicationNotifications: MedicationNotifications {
    func authorize() async throws -> Bool {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { return false }
        return await allowed()
    }
    func allowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) && settings.alertSetting != .disabled
    }
    func apply(_ plans: [MedicationPlan]) async throws {
        let center = UNUserNotificationCenter.current()
        let wanted = Set(plans.flatMap(\.notificationIDs))
        let pending = await center.pendingNotificationRequests()
        // Remove only our deleted/disabled schedules. The existing daily journal reminder is preserved.
        let stale = pending.map(\.identifier).filter { $0.hasPrefix("oncare-med.") && !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        center.removeDeliveredNotifications(withIdentifiers: stale)
        for plan in plans where plan.enabled {
            for weekday in plan.weekdays.sorted() {
                let content = UNMutableNotificationContent()
                content.title = "복용 일정을 확인할 시간"
                content.body = "온케어에서 등록한 약과 복용 방법을 확인하세요."
                content.sound = .default
                content.userInfo = ["oncare-route": "medications"]
                let date = DateComponents(hour: plan.hour, minute: plan.minute, weekday: weekday)
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                try await center.add(UNNotificationRequest(identifier: "oncare-med.\(plan.id).\(weekday)", content: content, trigger: trigger))
            }
        }
    }
}
@MainActor final class MedicationStore: ObservableObject {
    @Published private(set) var state = MedicationState()
    @Published private(set) var readable = true
    @Published private(set) var status = "알림 권한 확인 전"
    @Published var message: String?
    private let file: URL
    private let notifications: any MedicationNotifications
    private var refreshing = false
    private var refreshNeeded = false
    private static let registrationError = "알림 등록을 완료하지 못했어요. 알림 상태 다시 확인을 눌러주세요."
    init(directory: URL? = nil, notifications: (any MedicationNotifications)? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("medications-v1.json")
        self.notifications = notifications ?? SystemMedicationNotifications()
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { let loaded = try JSONDecoder().decode(MedicationState.self, from: Data(contentsOf: file)); try loaded.validate(); state = loaded }
        catch { readable = false; message = "투약 일정을 읽지 못했어요. 원본 파일은 보관하며 덮어쓰지 않습니다." }
    }
    private func persist(_ next: MedicationState) -> Bool {
        guard readable else { return false }
        do { try next.validate(); try JSONEncoder().encode(next).write(to: file, options: .atomic); state = next; return true }
        catch { message = "투약 일정을 저장하지 못했어요. 기존 일정은 유지됩니다."; return false }
    }
    func save(_ plan: MedicationPlan) async -> Bool {
        do {
            try plan.validate()
            if plan.enabled {
                guard try await notifications.authorize() else { message = "알림 권한이 필요해요. 설정에서 허용하거나 알림을 끄고 저장해주세요."; return false }
            }
            var next = state
            if let index = next.plans.firstIndex(where: { $0.id == plan.id }) { next.plans[index] = plan }
            else { next.plans.append(plan) }
            guard persist(next) else { return false }
            await refresh(); return true
        } catch { message = "이름·시간·요일을 확인해주세요. 일정은 최대 8개까지 등록할 수 있어요."; return false }
    }
    func remove(_ id: String) async {
        var next = state; next.plans.removeAll { $0.id == id }
        for key in Array(next.checks.keys) { next.checks[key]?.remove(id) }
        if persist(next) { await refresh() }
    }
    func checked(_ id: String, now: Date = Date()) -> Bool { state.checks[dateKey(now)]?.contains(id) == true }
    func replaceFromBackup(_ imported: MedicationState) async -> Bool {
        do {
            try imported.validate()
            var replacement = imported
            replacement.plans = imported.plans.map { var plan = $0; plan.enabled = false; return plan }
            if !readable {
                let preserved = file.deletingLastPathComponent().appendingPathComponent("medications-preserved-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: preserved)
            }
            let previousReadable = readable; readable = true
            guard persist(replacement) else { readable = previousReadable; return false }
            message = "투약 백업을 가져왔어요. 알림은 모두 꺼져 있으며 직접 켤 수 있어요."
            await refresh(); return true
        } catch { message = "투약 백업을 복원하지 못했어요. 기존 일정과 원본 파일은 유지됩니다."; return false }
    }
    func toggleTaken(_ id: String, now: Date = Date()) {
        guard let plan = state.plans.first(where: { $0.id == id }), plan.weekdays.contains(Calendar.current.component(.weekday, from: now)) else { return }
        var next = state
        let key = dateKey(now), cutoff = dateKey(Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now)
        next.checks = next.checks.filter { $0.key >= cutoff && $0.key <= key }
        var today = next.checks[key] ?? []
        if today.contains(id) { today.remove(id) } else { today.insert(id) }
        next.checks[key] = today; _ = persist(next)
    }
    func refresh() async {
        if refreshing { refreshNeeded = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
        refreshNeeded = false
        guard readable else { status = "일정 파일 확인 필요"; return }
        let allowed = await notifications.allowed()
        do {
            try await notifications.apply(allowed ? state.plans : state.plans.map { plan in var disabled = plan; disabled.enabled = false; return disabled })
            status = allowed ? "알림 권한 허용 · 시간·요일 반복" : "알림 권한 꺼짐 · 설정 확인 필요"
            if message == Self.registrationError { message = nil }
        } catch { status = "일정 저장됨 · 알림 등록 재시도 필요"; message = Self.registrationError }
        } while refreshNeeded
    }
}
@MainActor final class MedicationNavigation: ObservableObject {
    static let shared = MedicationNavigation()
    @Published var pending: UUID?
}
