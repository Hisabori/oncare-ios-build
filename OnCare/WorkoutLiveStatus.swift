import ActivityKit
import Foundation

@MainActor enum WorkoutLiveStatus {
    @available(iOS 16.2, *)
    static func state(for session: WorkoutSession, at now: Date) throws -> CareWorkoutAttributes.ContentState {
        let elapsed = try session.elapsed(at: now)
        let start = now.addingTimeInterval(-elapsed)
        return CareWorkoutAttributes.ContentState(running: session.running, elapsedSeconds: Int(elapsed), timerStart: start, timerEnd: start.addingTimeInterval(86400))
    }
    private static var pending: Task<Void, Never>?
    static func reconcile(_ session: WorkoutSession?, enabled: Bool, valid: Bool) {
        let previous = pending
        pending = Task {
            await previous?.value
            guard #available(iOS 16.2, *) else { return }
            let existing = Activity<CareWorkoutAttributes>.activities
            guard enabled, valid, let session, session.finishedAt == nil else {
                for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            let now = Date()
            guard let state = try? state(for: session, at: now) else { return }
            let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(8 * 3600))
            var matching: Activity<CareWorkoutAttributes>?
            for activity in existing {
                if activity.attributes.sessionID == session.id, matching == nil { matching = activity }
                else { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            if let matching { await matching.update(content) }
            else if ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Activity.request(attributes: CareWorkoutAttributes(sessionID: session.id, goalMinutes: session.goalMinutes), content: content, pushType: nil)
            }
        }
    }
}
