import Foundation
import UserNotifications

@MainActor protocol CareNotificationCenter {
    func authorize() async throws -> Bool
    func schedule(hour: Int, minute: Int) async throws
    func remove()
}
@MainActor struct SystemCareNotifications: CareNotificationCenter {
    func authorize() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func schedule(hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "오늘의 나를 돌아볼 시간"; content.body = "마음과 작은 실천을 온케어에 남겨보세요."; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        // The same identifier replaces the old request only after successful scheduling.
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: ReminderScheduler.identifier, content: content, trigger: trigger))
    }
    func remove() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ReminderScheduler.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [ReminderScheduler.identifier])
    }
}
@MainActor enum ReminderScheduler {
    static let identifier = "oncare-daily"
    static func update(enabled: Bool, hour: Int, minute: Int, defaults: UserDefaults = .standard, center: (any CareNotificationCenter)? = nil) async throws -> Bool {
        let center = center ?? SystemCareNotifications()
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { throw CareError.invalid }
        if enabled {
            guard try await center.authorize() else { center.remove(); defaults.set(false, forKey: "reminder-enabled"); return false }
            try await center.schedule(hour: hour, minute: minute)
        } else { center.remove() }
        defaults.set(hour, forKey: "reminder-hour"); defaults.set(minute, forKey: "reminder-minute"); defaults.set(enabled, forKey: "reminder-enabled")
        return true
    }
}
