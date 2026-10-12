import ActivityKit
import Foundation

@MainActor enum CareLiveStatus {
    static func update(message: String, count: Int?, syncing: Bool) async {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = CareSyncAttributes.ContentState(message: message, count: count, syncing: syncing)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
        if syncing {
            if let activity = Activity<CareSyncAttributes>.activities.first { await activity.update(content) }
            else { _ = try? Activity.request(attributes: CareSyncAttributes(), content: content, pushType: nil) }
        } else {
            for activity in Activity<CareSyncAttributes>.activities { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60))) }
        }
    }
    static func finish() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<CareSyncAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
