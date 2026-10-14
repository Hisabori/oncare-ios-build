import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct CareWorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var running: Bool
        var elapsedSeconds: Int
        var timerStart: Date
        var timerEnd: Date
    }
    var sessionID: String
    var goalMinutes: Int
}
