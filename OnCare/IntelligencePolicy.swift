import Foundation

enum IntelligencePolicy {
    static let focuses = ["균형 있게", "기록 돌아보기", "작은 실천"]
    static func period(_ days: Int) -> Int { days == 30 ? 30 : 7 }
    static func article(_ text: String) -> String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2700)) }
    static func validated(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 4000,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) else { throw CareError.unreadable }
        return value
    }
}
