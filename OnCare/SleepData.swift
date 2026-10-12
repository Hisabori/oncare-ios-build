import Foundation

enum SleepStageType: String, Codable, CaseIterable, Hashable {
    case awake, light, deep, rem, sleeping, unknown
    var title: String {
        switch self {
        case .awake: return "깨어 있음"
        case .light: return "얕은 수면"
        case .deep: return "깊은 수면"
        case .rem: return "REM 수면"
        case .sleeping: return "수면 · 세부 단계 없음"
        case .unknown: return "미분류"
        }
    }
}
struct SleepStage: Codable, Equatable {
    var start: Date
    var end: Date
    var type: SleepStageType
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}
struct SleepDetails: Codable, Equatable {
    var stages: [SleepStage] = []
    var originApp: String? = nil
    var deviceName: String? = nil
    var recordingMethod: String? = nil
    func validate(for entry: Entry) throws {
        guard entry.kind == "수면", let start = entry.bedTime, let end = entry.wakeTime, let awake = entry.awakeMinutes,
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              start.timeIntervalSince1970 > 0, end == entry.date,
              let hours = SleepPlan.measuredHours(start: start, end: end, awake: awake),
              entry.value.isFinite, abs(hours - entry.value) <= 1.0 / 3600,
              stages.count <= 2048 else { throw CareError.invalid }
        func validText(_ text: String?, limit: Int) -> Bool {
            guard let text else { return true }
            return text.count <= limit && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard validText(originApp, limit: 200), validText(deviceName, limit: 200), validText(recordingMethod, limit: 32),
              recordingMethod == nil || ["active", "automatic", "manual", "unknown"].contains(recordingMethod!) else { throw CareError.invalid }
        let ordered = stages.sorted { $0.start < $1.start }
        var previousEnd = start, awakeFromStages: Double = 0
        for stage in ordered {
            guard stage.start.timeIntervalSince1970.isFinite, stage.end.timeIntervalSince1970.isFinite,
                  stage.start >= start, stage.end <= end, stage.start < stage.end,
                  stage.start >= previousEnd else { throw CareError.invalid }
            previousEnd = stage.end
            if stage.type == .awake { awakeFromStages += stage.minutes }
        }
        // Missing segments remain unclassified. Only explicit awake segments are subtracted.
        if !stages.isEmpty { guard abs(awakeFromStages - awake) <= 1.0 / 60 else { throw CareError.invalid } }
    }
}

struct SleepAnalysis {
    let sessionMinutes: Double
    let sleepMinutes: Double
    let awakeMinutes: Double
    let stageMinutes: [SleepStageType: Double]
    let coverage: Double
    let unclassifiedMinutes: Double
    let hasStages: Bool
    let sourceLabel: String
    let deviceName: String?
    let originApp: String?
    let recordingMethodLabel: String?
    let isGalaxyWatch: Bool
    let needsSourceConfirmation: Bool
    var efficiency: Double { min(1, max(0, sleepMinutes / sessionMinutes)) }
    func minutes(for type: SleepStageType) -> Double { stageMinutes[type] ?? 0 }

    init?(_ entry: Entry) {
        guard entry.kind == "수면", let start = entry.bedTime, let end = entry.wakeTime, let awake = entry.awakeMinutes,
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              start.timeIntervalSince1970 > 0, end == entry.date,
              let hours = SleepPlan.measuredHours(start: start, end: end, awake: awake),
              entry.value.isFinite, entry.value > 0, entry.value <= 24, abs(hours - entry.value) < 0.001 else { return nil }
        if let details = entry.sleep { do { try details.validate(for: entry) } catch { return nil } }
        sessionMinutes = end.timeIntervalSince(start) / 60
        sleepMinutes = entry.value * 60; awakeMinutes = awake
        let stages = entry.sleep?.stages ?? []
        var values: [SleepStageType: Double] = [:]
        for stage in stages { values[stage.type, default: 0] += stage.minutes }
        stageMinutes = values
        let classified = values.filter { $0.key != .unknown }.values.reduce(0, +)
        coverage = min(1, max(0, classified / sessionMinutes))
        unclassifiedMinutes = max(0, sessionMinutes - classified)
        hasStages = classified > 0
        deviceName = entry.sleep?.deviceName
        originApp = entry.sleep?.originApp
        let device = (deviceName ?? "").lowercased().filter { !$0.isWhitespace }
        isGalaxyWatch = device.contains("galaxywatch") || device.contains("갤럭시워치")
        let imported = entry.source?.hasPrefix("health-connect:") == true || originApp != nil || deviceName != nil
        needsSourceConfirmation = imported && (deviceName == nil || !hasStages)
        let app: String
        if originApp == "com.sec.android.app.shealth" { app = "삼성 헬스" }
        else if let originApp { app = originApp }
        else { app = "Health Connect" }
        if imported {
            sourceLabel = deviceName.map { $0 + " · " + app } ?? app + " · 기기 출처 확인 필요"
        } else { sourceLabel = "직접 기록" }
        switch entry.sleep?.recordingMethod {
        case "automatic": recordingMethodLabel = "자동 기록"
        case "active": recordingMethodLabel = "활동 중 기록"
        case "manual": recordingMethodLabel = "수동 입력"
        case "unknown": recordingMethodLabel = "기록 방식 확인 필요"
        default: recordingMethodLabel = nil
        }
    }
}
extension Entry {
    var sleepAnalysis: SleepAnalysis? { SleepAnalysis(self) }
}
