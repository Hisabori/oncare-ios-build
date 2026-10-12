import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct CareSyncAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
        var count: Int?
        var syncing: Bool
    }
    var title: String = "온케어 건강 연결"
}
