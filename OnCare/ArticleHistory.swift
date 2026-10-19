import Foundation

enum ArticleHistory {
    static func normalized(_ values: [String], known: Set<String>) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for value in values where known.contains(value) && seen.insert(value).inserted {
            result.append(value)
            if result.count == 10 { break }
        }
        return result
    }
}
